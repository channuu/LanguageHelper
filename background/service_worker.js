// ================================================================
// background/service_worker.js  — chrome.storage.local 버전 (Firebase 없이 동작)
// Firebase 연동은 나중에 추가 예정
// ================================================================

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message, sender).then(sendResponse).catch(err => {
    sendResponse({ success: false, error: err.message });
  });
  return true;
});

async function handleMessage(message, sender) {
  switch (message.type) {

    case "SAVE_SENTENCE": {
      const { sentence } = message.payload;
      const result = await chrome.storage.local.get("sentences");
      const sentences = result.sentences || [];
      const newItem = {
        id: Date.now().toString(),
        english: sentence.english,
        source: sentence.source || "unknown",
        sourceUrl: sentence.sourceUrl || "",
        videoTitle: sentence.videoTitle || "",
        savedAt: new Date().toISOString()
      };
      sentences.unshift(newItem);
      // 최대 200개 보관
      if (sentences.length > 200) sentences.splice(200);
      await chrome.storage.local.set({ sentences });
      return { success: true, id: newItem.id };
    }

    case "GET_SENTENCES": {
      const result = await chrome.storage.local.get("sentences");
      return { success: true, sentences: result.sentences || [] };
    }

    case "DELETE_SENTENCE": {
      const result = await chrome.storage.local.get("sentences");
      const sentences = (result.sentences || []).filter(s => s.id !== message.payload.id);
      await chrome.storage.local.set({ sentences });
      return { success: true };
    }

    case "TOGGLE_EXTENSION": {
      const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tabs[0]) {
        chrome.tabs.sendMessage(tabs[0].id, { type: "TOGGLE_OVERLAY" }).catch(() => {});
      }
      return { success: true };
    }

    default:
      return { success: false, error: "Unknown message type" };
  }
}
