// background/service_worker.js
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message).then(sendResponse).catch(err => {
    sendResponse({ success: false, error: err.message });
  });
  return true;
});

async function handleMessage(message) {
  switch (message.type) {

    case 'FETCH_CAPTIONS': {
      const base = message.payload.url.replace(/&fmt=[^&]*/g, '');
      for (const fmt of ['srv3', 'srv1', '']) {
        try {
          const url = fmt ? base + '&fmt=' + fmt : base;
          const res  = await fetch(url);
          const text = await res.text();
          if (text && text.length > 10) return { success: true, text, fmt };
        } catch (e) {
          console.warn('[EH BG] fetch captions fmt=' + fmt, e.message);
        }
      }
      return { success: false, error: 'all formats failed' };
    }

    case 'SAVE_WORD': {
      const result = await chrome.storage.local.get('eh-words');
      const words = result['eh-words'] || [];
      words.unshift(message.payload);
      if (words.length > 500) words.splice(500);
      await chrome.storage.local.set({ 'eh-words': words });
      return { success: true, id: message.payload.id };
    }

    case 'SAVE_SENTENCE': {
      const result = await chrome.storage.local.get('eh-sentences');
      const sentences = result['eh-sentences'] || [];
      sentences.unshift(message.payload);
      if (sentences.length > 500) sentences.splice(500);
      await chrome.storage.local.set({ 'eh-sentences': sentences });
      return { success: true, id: message.payload.id };
    }

    case 'GET_ALL': {
      const result = await chrome.storage.local.get(['eh-words', 'eh-sentences']);
      return {
        success: true,
        words: result['eh-words'] || [],
        sentences: result['eh-sentences'] || []
      };
    }

    case 'DELETE_ITEM': {
      const { type, id } = message.payload;
      const key = type === 'word' ? 'eh-words' : 'eh-sentences';
      const result = await chrome.storage.local.get(key);
      const items = (result[key] || []).filter(i => i.id !== id);
      await chrome.storage.local.set({ [key]: items });
      return { success: true };
    }

    case 'TOGGLE_EXTENSION': {
      const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tabs[0]) chrome.tabs.sendMessage(tabs[0].id, { type: 'TOGGLE_OVERLAY' }).catch(() => {});
      return { success: true };
    }

    default:
      return { success: false, error: 'Unknown message type: ' + message.type };
  }
}
