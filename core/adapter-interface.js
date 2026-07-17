(function () {
  'use strict';

  window.EH = window.EH || {};

  /**
   * 모든 플랫폼 어댑터가 구현해야 하는 계약.
   * 신규 플랫폼 추가 = 이 클래스를 extends한 파일 하나만 adapters/ 에 추가.
   */
  class SubtitleAdapter {
    /** @returns {{ lang: string, cues: {start: number, end: number, text: string}[] }[]} */
    getSubtitleTracks() { throw new Error('getSubtitleTracks() not implemented'); }

    /** @returns {number} 현재 재생 위치 (초) */
    getCurrentTime() { throw new Error('getCurrentTime() not implemented'); }

    /** @param {number} seconds */
    seekTo(seconds) { throw new Error('seekTo() not implemented'); }

    /** @param {function({lang: string, text: string}[]): void} callback */
    onSubtitleChange(callback) { throw new Error('onSubtitleChange() not implemented'); }

    /** @param {function(number): void} callback */
    onTimeUpdate(callback) { throw new Error('onTimeUpdate() not implemented'); }

    /** @returns {{ platform: string, title: string, contentId: string }} */
    getPlatformMeta() { throw new Error('getPlatformMeta() not implemented'); }

    /** 이벤트 리스너 정리 */
    destroy() {}
  }

  const DEFAULT_SETTINGS = { enSize: 22, nativeSize: 18, mode: 'both', nativeLang: 'ko' };

  /**
   * 어댑터가 준비되면 호출. 코어 모듈들을 순서대로 초기화한다.
   * @param {SubtitleAdapter} adapter
   */
  async function init(adapter) {
    if (!(adapter instanceof SubtitleAdapter)) {
      console.error('[EH] adapter must extend SubtitleAdapter');
      return;
    }
    window.EH.adapter = adapter;

    const stored = await chrome.storage.local.get('eh-settings');
    window.EH.settings = { ...DEFAULT_SETTINGS, ...(stored['eh-settings'] || {}) };

    // 각 코어 모듈은 window.EH.* 에 등록 후 이 함수를 기다린다
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.setup(adapter);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.setup(adapter);
    if (window.EH.WordPopup)      window.EH.WordPopup.setup(adapter);
  }

  function applySettings(patch) {
    window.EH.settings = { ...window.EH.settings, ...patch };
    chrome.storage.local.set({ 'eh-settings': window.EH.settings });
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.applySettings(window.EH.settings);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.applySettings(window.EH.settings);
  }

  window.EH.SubtitleAdapter = SubtitleAdapter;
  window.EH.init = init;
  window.EH.applySettings = applySettings;
  window.EH.settings = { ...DEFAULT_SETTINGS };

  // 팝업 / service worker 메시지 수신
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === 'TOGGLE_OVERLAY') {
      window.EH.SubtitleEngine?.toggle();
    }
    if (msg.type === 'TOGGLE_PANEL') {
      window.EH.ScriptPanel?.toggle(msg.visible);
    }
    if (msg.type === 'APPLY_SETTINGS') {
      applySettings(msg.settings);
    }
  });
})();
