(function () {
  'use strict';

  let popupEl = null;

  function createDOM() {
    if (document.getElementById('eh-word-popup')) {
      popupEl = document.getElementById('eh-word-popup');
      return;
    }
    popupEl = document.createElement('div');
    popupEl.id = 'eh-word-popup';
    document.body.appendChild(popupEl);

    // 팝업 바깥 클릭 시 닫기
    document.addEventListener('click', (e) => {
      if (!popupEl.contains(e.target)) hide();
    });
  }

  function hide() {
    if (popupEl) popupEl.classList.remove('visible');
  }

  function positionPopup(clientX, clientY) {
    const margin = 12;
    const pw = popupEl.offsetWidth || 260;
    const ph = popupEl.offsetHeight || 200;
    let x = clientX + margin;
    let y = clientY - ph / 2;
    if (x + pw > window.innerWidth - margin) x = clientX - pw - margin;
    if (y < margin) y = margin;
    if (y + ph > window.innerHeight - margin) y = window.innerHeight - ph - margin;
    popupEl.style.left = x + 'px';
    popupEl.style.top  = y + 'px';
  }

  async function fetchDefinition(word) {
    try {
      const res = await fetch(`https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`);
      if (!res.ok) return null;
      const data = await res.json();
      const entry = data[0];
      return {
        phonetic: entry.phonetic || entry.phonetics?.[0]?.text || '',
        definition: entry.meanings?.[0]?.definitions?.[0]?.definition || ''
      };
    } catch (e) {
      return null;
    }
  }

  async function show(word, sentence, translation, timestamp, clientX, clientY) {
    if (!popupEl) return;

    // 로딩 상태로 즉시 표시
    popupEl.innerHTML = `
      <div class="eh-popup-word">${esc(word)}</div>
      <div class="eh-popup-loading">불러오는 중...</div>
    `;
    popupEl.classList.add('visible');
    positionPopup(clientX, clientY);

    // 사전 API 호출
    const dict = await fetchDefinition(word);

    popupEl.innerHTML = `
      <div class="eh-popup-word">${esc(word)}</div>
      ${dict?.phonetic ? `<div class="eh-popup-phonetic">${esc(dict.phonetic)}</div>` : ''}
      <div class="eh-popup-divider"></div>
      <div class="eh-popup-def">${esc(dict?.definition || '정의를 찾을 수 없습니다.')}</div>
      ${sentence ? `<div class="eh-popup-sentence">"${esc(sentence)}"</div>` : ''}
      <div class="eh-popup-actions">
        <button class="eh-popup-btn" id="eh-save-word">단어 저장</button>
        <button class="eh-popup-btn" id="eh-save-sent">문장 저장</button>
      </div>
    `;

    // 팝업 높이가 바뀌었으므로 재위치
    positionPopup(clientX, clientY);

    document.getElementById('eh-save-word').addEventListener('click', () => {
      window.EH.Storage.saveWord({
        word, definition: dict?.definition || '',
        sentence, translation, timestamp
      }).then(() => {
        window.EH.showToast?.(`✓ "${word}" 저장됨`);
        hide();
      });
    });

    document.getElementById('eh-save-sent').addEventListener('click', () => {
      window.EH.Storage.saveSentence({ original: sentence, translation, timestamp })
        .then(() => {
          window.EH.showToast?.('✓ 문장 저장됨');
          hide();
        });
    });
  }

  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function setup() {
    createDOM();
  }

  window.EH = window.EH || {};
  window.EH.WordPopup = { setup, show, hide };
})();
