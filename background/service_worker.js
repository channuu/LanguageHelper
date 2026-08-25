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

    // 스크립트 PDF 내보내기 — 콘텐츠 스크립트가 만든 HTML을 받아 확장 페이지로
    // 넘긴다. HTML을 URL 쿼리로 넘기기엔 너무 커서(장편 영화 수백 KB)
    // storage.session에 임시로 두고 id만 전달한다. 저장을 콘텐츠 스크립트가
    // 아니라 여기서 하는 이유는 storage.session의 기본 접근 수준이
    // TRUSTED_CONTEXTS라 콘텐츠 스크립트에서는 접근할 수 없기 때문이다.
    case 'EH_EXPORT_PRINT': {
      const html = message.payload && message.payload.html;
      if (!html) return { success: false, error: 'no html' };
      const id = crypto.randomUUID();
      try {
        await chrome.storage.session.set({ ['eh_print_' + id]: html });
      } catch (err) {
        console.error('[EH BG] print session set failed', err);
        return { success: false, error: err.message };
      }
      await chrome.tabs.create({
        url: chrome.runtime.getURL('export/print.html?id=' + id)
      });
      return { success: true, id };
    }

    default:
      return { success: false, error: 'Unknown message type: ' + message.type };
  }
}
