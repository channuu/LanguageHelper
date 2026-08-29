// background/service_worker.js
import { getAuth, signOutLocal } from '../cloud/auth.js';
import {
  syncNow, ensureMigrated, queueDelete, getSyncStatus, clearLocalData
} from '../cloud/sync.js';

const LAST_UID_KEY = 'eh-last-uid';
const SUPPORTED_MATCHES = [
  'https://www.youtube.com/*',
  'https://www.netflix.com/*',
  'https://www.disneyplus.com/*',
  'https://*.coupangplay.com/*'
];

/** 열려 있는 지원 플랫폼 탭들에 인증 상태 변화를 알린다. */
async function broadcastAuthChanged() {
  const tabs = await chrome.tabs.query({ url: SUPPORTED_MATCHES });
  for (const tab of tabs) {
    // 콘텐츠 스크립트가 아직 없는 탭은 조용히 무시한다.
    chrome.tabs.sendMessage(tab.id, { type: 'EH_AUTH_CHANGED' }).catch(() => {});
  }
}

/** 다른 계정으로 로그인했으면 이전 계정의 로컬 캐시를 지운다 (설계 §4.4). */
async function handleAccountSwitch(uid) {
  const res = await chrome.storage.local.get(LAST_UID_KEY);
  const lastUid = res[LAST_UID_KEY];
  if (lastUid && lastUid !== uid) {
    await clearLocalData();
  }
  await chrome.storage.local.set({ [LAST_UID_KEY]: uid });
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message).then(sendResponse).catch(err => {
    sendResponse({ success: false, error: err.message });
  });
  return true;
});

async function handleMessage(message) {
  const AUTH_REQUIRED = ['SAVE_WORD', 'SAVE_SENTENCE', 'GET_ALL', 'DELETE_ITEM'];
  if (AUTH_REQUIRED.includes(message.type) && !(await getAuth())) {
    return { success: false, error: 'auth_required' };
  }

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
      await ensureMigrated();
      const result = await chrome.storage.local.get('eh-words');
      const words = result['eh-words'] || [];
      words.unshift(message.payload);
      if (words.length > 500) words.splice(500);
      await chrome.storage.local.set({ 'eh-words': words });
      // 로컬 저장은 이미 끝났다. 업로드 실패는 미동기 상태로 남을 뿐이다.
      syncNow().catch(err => console.warn('[EH BG] sync after save', err));
      return { success: true, id: message.payload.id };
    }

    case 'SAVE_SENTENCE': {
      await ensureMigrated();
      const result = await chrome.storage.local.get('eh-sentences');
      const sentences = result['eh-sentences'] || [];
      sentences.unshift(message.payload);
      if (sentences.length > 500) sentences.splice(500);
      await chrome.storage.local.set({ 'eh-sentences': sentences });
      syncNow().catch(err => console.warn('[EH BG] sync after save', err));
      return { success: true, id: message.payload.id };
    }

    case 'GET_ALL': {
      await ensureMigrated();
      const result = await chrome.storage.local.get(['eh-words', 'eh-sentences']);
      return {
        success: true,
        words: result['eh-words'] || [],
        sentences: result['eh-sentences'] || []
      };
    }

    case 'DELETE_ITEM': {
      const { type, id } = message.payload;
      const entity = type === 'word' ? 'words' : 'sentences';
      const key = 'eh-' + entity;
      const result = await chrome.storage.local.get(key);
      const items = (result[key] || []).filter(i => i.id !== id);
      await chrome.storage.local.set({ [key]: items });
      await queueDelete(entity, id);
      syncNow().catch(err => console.warn('[EH BG] sync after delete', err));
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
        url: chrome.runtime.getURL('export/print.html#id=' + id)
      });
      return { success: true, id };
    }

    case 'EH_AUTH_STATE': {
      const auth = await getAuth();
      return { success: true, signedIn: !!auth, email: auth ? auth.email : null };
    }

    case 'EH_OPEN_LOGIN': {
      await chrome.tabs.create({ url: chrome.runtime.getURL('auth/login.html') });
      return { success: true };
    }

    case 'EH_AUTH_CHANGED': {
      const auth = await getAuth();
      if (auth) await handleAccountSwitch(auth.uid);
      const result = await syncNow();
      await broadcastAuthChanged();
      return { success: true, pending: result.pending };
    }

    case 'EH_SYNC_NOW': {
      const result = await syncNow();
      return { success: result.ok, pending: result.pending };
    }

    case 'EH_SYNC_STATUS': {
      const status = await getSyncStatus();
      return { success: true, ...status };
    }

    case 'EH_SIGN_OUT': {
      // 로그아웃 전에 밀린 것을 먼저 밀어낸다. 남으면 호출자가 확인받아야
      // 한다 — 로그아웃은 로컬 캐시를 비우므로 미동기 항목이 유실된다.
      const result = await syncNow();
      if (result.pending > 0 && !(message.payload && message.payload.force)) {
        return { success: false, error: 'pending', pending: result.pending };
      }
      await signOutLocal();
      await clearLocalData();
      await chrome.storage.local.remove('eh-last-uid');
      await broadcastAuthChanged();
      return { success: true, pending: 0 };
    }

    default:
      return { success: false, error: 'Unknown message type: ' + message.type };
  }
}

// 서비스워커는 수시로 종료된다. 시작할 때마다 한 번 맞추고,
// 그 뒤로는 알람으로 밀린 것을 밀어낸다.
chrome.runtime.onStartup.addListener(() => {
  syncNow().catch(err => console.warn('[EH BG] startup sync', err));
});

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create('eh-sync', { periodInMinutes: 15 });
  syncNow().catch(err => console.warn('[EH BG] install sync', err));
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== 'eh-sync') return;
  syncNow().catch(err => console.warn('[EH BG] alarm sync', err));
});
