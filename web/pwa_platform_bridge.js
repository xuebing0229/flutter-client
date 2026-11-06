(() => {
  const DB_NAME = 'adventurers-guild-web-assets-v1';
  const STORE_NAME = 'referenceImages';
  let assetDbPromise = null;
  let deferredPwaInstallPrompt = null;
  let pwaInstalled =
    (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) ||
    window.navigator.standalone === true;

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    deferredPwaInstallPrompt = event;
  });

  window.addEventListener('appinstalled', () => {
    pwaInstalled = true;
    deferredPwaInstallPrompt = null;
  });

  function requestResult(request) {
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error('IndexedDB request failed'));
    });
  }

  function transactionDone(transaction) {
    return new Promise((resolve, reject) => {
      transaction.oncomplete = () => resolve();
      transaction.onerror = () =>
        reject(transaction.error || new Error('IndexedDB transaction failed'));
      transaction.onabort = () =>
        reject(transaction.error || new Error('IndexedDB transaction aborted'));
    });
  }

  function openAssetDb() {
    if (!('indexedDB' in window)) {
      return Promise.reject(new Error('当前浏览器不支持本地素材存储'));
    }
    if (!assetDbPromise) {
      assetDbPromise = new Promise((resolve, reject) => {
        const request = indexedDB.open(DB_NAME, 1);
        request.onupgradeneeded = () => {
          const db = request.result;
          if (!db.objectStoreNames.contains(STORE_NAME)) {
            db.createObjectStore(STORE_NAME);
          }
        };
        request.onsuccess = () => {
          const db = request.result;
          db.onversionchange = () => {
            db.close();
            assetDbPromise = null;
          };
          resolve(db);
        };
        request.onerror = () => {
          assetDbPromise = null;
          reject(request.error || new Error('打开本地素材库失败'));
        };
        request.onblocked = () => {
          assetDbPromise = null;
          reject(new Error('本地素材库升级被其他页面占用'));
        };
      });
    }
    return assetDbPromise;
  }

  function base64ToBytes(encoded) {
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  function bytesToBase64(bytes) {
    let binary = '';
    const chunkSize = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      binary += String.fromCharCode(
        ...bytes.subarray(offset, Math.min(bytes.length, offset + chunkSize)),
      );
    }
    return btoa(binary);
  }

  window.adventurersGuildStorageGet = (key) =>
    window.localStorage.getItem(String(key));

  window.adventurersGuildStorageSet = (key, value) => {
    window.localStorage.setItem(String(key), String(value));
  };

  window.adventurersGuildStorageRemove = (key) => {
    window.localStorage.removeItem(String(key));
  };

  window.adventurersGuildPwaInstallState = () => {
    if (pwaInstalled) return 'installed';
    if (deferredPwaInstallPrompt) return 'prompt';
    const userAgent = window.navigator.userAgent || '';
    const isIos =
      /iPad|iPhone|iPod/.test(userAgent) ||
      (window.navigator.platform === 'MacIntel' &&
        window.navigator.maxTouchPoints > 1);
    return isIos ? 'ios' : 'manual';
  };

  window.adventurersGuildPromptPwaInstall = async () => {
    if (pwaInstalled) return 'installed';
    const prompt = deferredPwaInstallPrompt;
    if (!prompt) return window.adventurersGuildPwaInstallState();
    deferredPwaInstallPrompt = null;
    await prompt.prompt();
    const choice = await prompt.userChoice;
    if (choice && choice.outcome === 'accepted') {
      return 'accepted';
    }
    return 'dismissed';
  };

  window.adventurersGuildDownloadBytes = (fileName, mimeType, base64Data) => {
    const bytes = base64ToBytes(String(base64Data));
    const blob = new Blob([bytes], { type: String(mimeType) });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = String(fileName);
    anchor.style.display = 'none';
    document.body.appendChild(anchor);
    try {
      anchor.click();
    } finally {
      anchor.remove();
      URL.revokeObjectURL(url);
    }
  };

  window.adventurersGuildPickImage = () =>
    new Promise((resolve, reject) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/png,image/jpeg,image/webp';
      input.style.display = 'none';

      const cleanup = () => {
        input.remove();
      };

      input.onchange = async () => {
        try {
          const file = input.files && input.files[0];
          if (!file) {
            cleanup();
            resolve('');
            return;
          }
          const bytes = new Uint8Array(await file.arrayBuffer());
          cleanup();
          resolve(
            JSON.stringify({
              name: file.name || 'image.png',
              data: bytesToBase64(bytes),
            }),
          );
        } catch (error) {
          cleanup();
          reject(error);
        }
      };

      input.oncancel = () => {
        cleanup();
        resolve('');
      };

      document.body.appendChild(input);
      input.click();
    });


  window.adventurersGuildAssetRead = async (key) => {
    const db = await openAssetDb();
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const done = transactionDone(transaction);
    const value = await requestResult(
      transaction.objectStore(STORE_NAME).get(String(key)),
    );
    await done;
    if (value == null) return '';
    if (typeof value === 'string') return value;
    if (value instanceof ArrayBuffer) {
      return bytesToBase64(new Uint8Array(value));
    }
    if (ArrayBuffer.isView(value)) {
      return bytesToBase64(
        new Uint8Array(value.buffer, value.byteOffset, value.byteLength),
      );
    }
    if (Array.isArray(value)) {
      return bytesToBase64(Uint8Array.from(value));
    }
    throw new Error('浏览器里的素材数据格式无效');
  };

  window.adventurersGuildAssetWrite = async (key, base64Data) => {
    const db = await openAssetDb();
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const done = transactionDone(transaction);
    transaction.objectStore(STORE_NAME).put(String(base64Data), String(key));
    await done;
    return 'ok';
  };

  window.adventurersGuildAssetDelete = async (key) => {
    const db = await openAssetDb();
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const done = transactionDone(transaction);
    transaction.objectStore(STORE_NAME).delete(String(key));
    await done;
    return 'ok';
  };
})();
