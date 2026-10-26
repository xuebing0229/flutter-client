let ocrPromise = null;

function base64ToBlob(encoded) {
  const binary = atob(String(encoded));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new Blob([bytes]);
}

async function getOcr() {
  if (!ocrPromise) {
    ocrPromise = (async () => {
      const { PaddleOCR } = await import(
        "https://esm.sh/@paddleocr/paddleocr-js@0.4.2?bundle"
      );
      return PaddleOCR.create({
        lang: "ch",
        ocrVersion: "PP-OCRv6",
        worker: false,
        ortOptions: {
          backend: "wasm",
          wasmPaths: "https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/",
          simd: true,
          numThreads: 1,
        },
      });
    })();
  }
  return ocrPromise;
}

window.adventurersGuildOcrRecognize = async function (base64Data) {
  const ocr = await getOcr();
  const [result] = await ocr.predict(base64ToBlob(base64Data));
  if (!result) throw new Error("PaddleOCR.js did not return a result");
  const lines = (result.items || []).map((item) => {
    const points = Array.isArray(item.poly) ? item.poly : [];
    const xs = [];
    const ys = [];
    for (const point of points) {
      if (Array.isArray(point) && point.length >= 2) {
        const x = Number(point[0]);
        const y = Number(point[1]);
        if (Number.isFinite(x) && Number.isFinite(y)) {
          xs.push(x);
          ys.push(y);
        }
      }
    }
    return {
      text: String(item.text || ""),
      left: xs.length ? Math.min(...xs) : 0,
      top: ys.length ? Math.min(...ys) : 0,
      right: xs.length ? Math.max(...xs) : 0,
      bottom: ys.length ? Math.max(...ys) : 0,
      confidence: Number.isFinite(Number(item.score)) ? Number(item.score) : 1,
    };
  });
  return JSON.stringify({
    imageWidth: Number(result.image?.width || 0),
    imageHeight: Number(result.image?.height || 0),
    lines,
  });
};

window.adventurersGuildOcrRelease = async function () {
  if (ocrPromise) {
    try {
      const ocr = await ocrPromise;
      ocr.dispose?.();
    } finally {
      ocrPromise = null;
    }
  }
  return "ok";
};
