const ROOM_RE = /^[0-9a-f]{32}$/;
const INBOX_RE = /^[A-Za-z0-9_-]{1,220}$/;
const TOPIC_RE =
  /^adventurers-guild-peer\/v1\/([0-9a-f]{32})\/inbox\/([A-Za-z0-9_-]{1,220})$/;
const MAX_MESSAGE_CHARS = 64 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/sync-health") {
      return Response.json({
        ok: true,
        service: "adventurers-guild-sync-relay",
        persistence: "none",
      });
    }

    if (url.pathname === "/sync") {
      if (request.method !== "GET") {
        return new Response("Method Not Allowed", { status: 405 });
      }
      if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
        return new Response("WebSocket upgrade required", { status: 426 });
      }

      const room = url.searchParams.get("room") || "";
      const inbox = url.searchParams.get("inbox") || "";
      if (!ROOM_RE.test(room) || !INBOX_RE.test(inbox)) {
        return new Response("Invalid relay address", { status: 400 });
      }

      const id = env.SYNC_ROOM.idFromName(room);
      return env.SYNC_ROOM.get(id).fetch(request);
    }

    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }
    return new Response("Not Found", { status: 404 });
  },
};

export class SyncRoom {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const room = url.searchParams.get("room") || "";
    const inbox = url.searchParams.get("inbox") || "";

    if (!ROOM_RE.test(room) || !INBOX_RE.test(inbox)) {
      return new Response("Invalid relay address", { status: 400 });
    }
    if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
      return new Response("WebSocket upgrade required", { status: 426 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    // Hibernatable WebSockets keep the connection alive without keeping the
    // Durable Object resident in memory while there is no traffic.
    this.ctx.acceptWebSocket(server, [`inbox:${inbox}`]);
    server.serializeAttachment({ room, inbox });

    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }

  async webSocketMessage(ws, message) {
    if (typeof message !== "string") {
      ws.close(1003, "Text frames only");
      return;
    }
    if (message.length > MAX_MESSAGE_CHARS) {
      ws.close(1009, "Relay frame too large");
      return;
    }

    let envelope;
    try {
      envelope = JSON.parse(message);
    } catch {
      return;
    }
    if (
      !envelope ||
      envelope.type !== "publish" ||
      typeof envelope.topic !== "string" ||
      typeof envelope.payload !== "string"
    ) {
      return;
    }

    const attachment = ws.deserializeAttachment();
    if (!attachment || !ROOM_RE.test(attachment.room || "")) {
      ws.close(1008, "Missing room attachment");
      return;
    }

    const topicMatch = TOPIC_RE.exec(envelope.topic);
    if (!topicMatch) return;

    const [, targetRoom, targetInbox] = topicMatch;
    if (targetRoom !== attachment.room) {
      // A socket is permanently scoped to one opaque room and cannot publish
      // into a different account room.
      return;
    }

    const outgoing = JSON.stringify({
      topic: envelope.topic,
      payload: envelope.payload,
    });
    if (outgoing.length > MAX_MESSAGE_CHARS) return;

    for (const peer of this.ctx.getWebSockets(`inbox:${targetInbox}`)) {
      if (peer === ws) continue;
      try {
        peer.send(outgoing);
      } catch {
        // The runtime will surface closed sockets through the close/error
        // handlers; one stale peer must not block other online devices.
      }
    }
  }

  async webSocketClose(ws, code, reason, wasClean) {
    // Cloudflare handles the close handshake for current compatibility dates.
    // No workspace data or presence state is persisted.
  }

  async webSocketError(ws, error) {
    try {
      ws.close(1011, "Relay socket error");
    } catch {}
  }
}
