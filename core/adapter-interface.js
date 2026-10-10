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

    /** @param {function(Array): void} callback — called once tracks are parsed and ready */
    onTracksReady(callback) {}

    /** @returns {{ platform: string, title: string, contentId: string }} */
    getPlatformMeta() { throw new Error('getPlatformMeta() not implemented'); }

    /** 이벤트 리스너 정리 */
    destroy() {}
  }

  const DEFAULT_SETTINGS = { enSize: 22, nativeSize: 18, mode: 'both', nativeLang: 'ko', cueLines: 2 };
  const ENABLED_KEY = 'eh-enabled';
  // 오버레이·스크립트 패널을 켜고 끈 상태. 사이트를 옮기거나 다음 영상으로
  // 넘어가도 매번 다시 열리지 않도록 기억한다.
  const UI_KEY = 'eh-ui';
  const DEFAULT_UI = { overlay: true, panel: true };

  // 툴바 팝업(popup/)의 "전체 기능" 스위치. 꺼져 있으면 이 페이지에 UI를
  // 아무것도 만들지 않는다 — 상단 바도, 오버레이도, 패널도.
  window.EH = window.EH || {};
  window.EH.enabled = true;

  // 전체 기능 on/off. 파괴하지 않고 멈추고 숨기기만 한다 — 그래야 다시 켤 때
  // 페이지 새로고침 없이 즉시 돌아온다. 예전에는 끌 때 DOM을 걷어내고
  // 어댑터를 destroy()했는데, 모듈의 상태와 리스너가 남아 패널이 되살아나는
  // 경로가 있었고(유튜브 applyMountStrategy의 재부착) 되살릴 방법이 없어
  // 켤 때 새로고침이 필요했다.
  function applyEnabled(enabled) {
    window.EH.enabled = enabled;
    // 플랫폼 자체 자막은 꺼져 있는 동안 다시 보여야 한다. 어댑터가 만든
    // 숨김 스타일을 지우지 않고 비활성화만 해서, 켤 때 그대로 되살린다.
    const nativeSubs = document.getElementById('eh-native-subs-style');
    if (nativeSubs) nativeSubs.disabled = !enabled;
    window.EH.SubtitleEngine?.setSuspended?.(!enabled);
    window.EH.ScriptPanel?.setSuspended?.(!enabled);
  }

  function _overlayVisible() {
    const el = document.getElementById('eh-overlay');
    return !!el && !el.classList.contains('hidden');
  }

  // core/script-panel.js의 _isPanelVisible()과 같은 판정 — 래퍼(임베드 모드)와
  // 패널 중 하나라도 hidden이면 보이지 않는 것으로 본다.
  function _panelVisible() {
    const panel = document.getElementById('eh-panel');
    if (!panel || panel.classList.contains('hidden')) return false;
    const wrapper = document.getElementById('eh-panel-wrapper');
    return !(wrapper && wrapper.classList.contains('hidden'));
  }

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

    const stored = await chrome.storage.local.get(['eh-settings', ENABLED_KEY, UI_KEY]);
    window.EH.settings = { ...DEFAULT_SETTINGS, ...(stored['eh-settings'] || {}) };
    window.EH.enabled = stored[ENABLED_KEY] !== false; // 저장된 적 없으면 켜짐
    const ui = { ...DEFAULT_UI, ...(stored[UI_KEY] || {}) };

    // 각 코어 모듈은 window.EH.* 에 등록 후 이 함수를 기다린다
    if (window.EH.SettingsPanel)  window.EH.SettingsPanel.setup(adapter);
    if (window.EH.LibraryPanel)   window.EH.LibraryPanel.setup(adapter);
    if (window.EH.SubtitleEngine) window.EH.SubtitleEngine.setup(adapter);
    if (window.EH.ScriptPanel)    window.EH.ScriptPanel.setup(adapter);
    if (window.EH.WordPopup)      window.EH.WordPopup.setup(adapter);

    // 두 모듈 다 켜진 상태로 만들어지므로, 지난번에 꺼 둔 것만 되돌린다.
    // 패널은 임베드↔밀어내기 모드가 정해진 뒤에 닫아야 레이아웃 보정까지
    // 함께 걷히므로 setup 이후에 부른다.
    if (!ui.overlay) window.EH.SubtitleEngine?.toggle();
    if (!ui.panel)   window.EH.ScriptPanel?.toggle(false);

    // 꺼진 상태로 들어왔다면 모듈을 세운 뒤 곧바로 멈춘다. 아예 만들지 않는
    // 편이 가벼워 보이지만, 그러면 다시 켤 때 새로고침이 필요해진다.
    if (!window.EH.enabled) applyEnabled(false);
  }

  function _saveUi(patch) {
    chrome.storage.local.get(UI_KEY, (stored) => {
      const next = { ...DEFAULT_UI, ...(stored[UI_KEY] || {}), ...patch };
      chrome.storage.local.set({ [UI_KEY]: next });
    });
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
  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    // 팝업이 스위치 상태를 그릴 때 쓰는 현재 상태. 전체 기능이 꺼져 있어도
    // 이 리스너는 살아 있으므로(모듈만 안 세운 것) 팝업이 다시 켤 수 있다.
    if (msg.type === 'EH_GET_STATE') {
      const meta = window.EH.enabled ? (window.EH.adapter?.getPlatformMeta?.() || {}) : {};
      sendResponse({
        ok: true,
        enabled: window.EH.enabled !== false,
        overlay: _overlayVisible(),
        panel: _panelVisible(),
        settings: window.EH.settings,
        platform: meta.platform || '',
        title: meta.title || ''
      });
      return;
    }

    if (msg.type === 'EH_SET_ENABLED') {
      const enabled = !!msg.enabled;
      chrome.storage.local.set({ [ENABLED_KEY]: enabled });
      applyEnabled(enabled);
      sendResponse({ ok: true, enabled });
      return;
    }

    if (msg.type === 'EH_OPEN_LIBRARY') {
      document.dispatchEvent(new CustomEvent('eh-library-toggle'));
      sendResponse({ ok: true });
      return;
    }

    if (msg.type === 'EH_OPEN_SETTINGS') {
      document.dispatchEvent(new CustomEvent('eh-settings-toggle'));
      sendResponse({ ok: true });
      return;
    }

    if (msg.type === 'EH_EXPORT') {
      const panel = window.EH.ScriptPanel;
      if (!panel) { sendResponse({ ok: false, error: 'panel not ready' }); return; }
      if (msg.format === 'pdf') panel.exportScriptPdf();
      else panel.exportScriptHtml();
      sendResponse({ ok: true });
      return;
    }

    if (msg.type === 'TOGGLE_OVERLAY') {
      const visible = window.EH.SubtitleEngine?.toggle();
      if (typeof visible === 'boolean') _saveUi({ overlay: visible });
      document.dispatchEvent(new CustomEvent('eh-overlay-toggled', { detail: { visible } }));
    }
    if (msg.type === 'TOGGLE_PANEL') {
      const visible = window.EH.ScriptPanel?.toggle(msg.visible);
      if (typeof visible === 'boolean') _saveUi({ panel: visible });
      document.dispatchEvent(new CustomEvent('eh-panel-toggled', { detail: { visible } }));
    }
    if (msg.type === 'APPLY_SETTINGS') {
      applySettings(msg.settings);
    }
  });
})();
