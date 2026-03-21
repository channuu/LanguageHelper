// background/service_worker.js

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message, sender).then(sendResponse).catch(err => {
    sendResponse({ success: false, error: err.message });
  });
  return true;
});

async function handleMessage(message, sender) {
  switch (message.type) {

    case "FETCH_CAPTIONS": {
      const base = message.payload.url.replace(/&fmt=[^&]*/g, "");
      for (const fmt of ["srv3", "srv1", ""]) {
        try {
          const fetchUrl = fmt ? base + "&fmt=" + fmt : base;
          const res  = await fetch(fetchUrl);
          const text = await res.text();
          if (text && text.length > 10) {
            console.log("[EnglishHelper BG] fmt=" + fmt + " success len=" + text.length);
            return { success: true, text, fmt };
          }
        } catch(e) {
          console.warn("[EnglishHelper BG] fmt=" + fmt + " failed:", e.message);
        }
      }
      return { success: false, error: "all formats failed" };
    }

    case "TRANSLATE_BATCH": {
      const texts = message.payload.texts;
      const results = new Array(texts.length).fill("");
      const CHUNK = 50;

      for (let i = 0; i < texts.length; i += CHUNK) {
        const chunk = texts.slice(i, i + CHUNK);
        try {
          const joined = chunk.join("\n");
          const url = "https://translate.googleapis.com/translate_a/single"
            + "?client=gtx&sl=en&tl=ko&dt=t&q=" + encodeURIComponent(joined);
          const res  = await fetch(url);
          const data = await res.json();
          const translated = (data[0] || []).map(seg => seg[0] || "").join("");
          const parts = translated.split("\n");
          for (let j = 0; j < chunk.length; j++) {
            results[i + j] = (parts[j] || "").trim() || chunk[j];
          }
        } catch(e) {
          console.warn("[EnglishHelper BG] translate chunk " + i + " failed:", e.message);
          for (let j = 0; j < chunk.length; j++) {
            results[i + j] = texts[i + j];
          }
        }
      }
      return { success: true, results };
    }

    case "SAVE_SENTENCE": {
      const sentence = message.payload.sentence;
      const result = await chrome.storage.local.get("sentences");
      const sentences = result.sentences || [];
      const newItem = {
        id: Date.now().toString(),
        english: sentence.english,
        context: sentence.context || "",
        source: sentence.source || "unknown",
        sourceUrl: sentence.sourceUrl || "",
        videoTitle: sentence.videoTitle || "",
        savedAt: new Date().toISOString()
      };
      sentences.unshift(newItem);
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
