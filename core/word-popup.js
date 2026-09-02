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

  async function lookup(term) {
    try {
      const res = await chrome.runtime.sendMessage({
        type: 'DICT_LOOKUP', payload: { term }
      });
      return (res && res.success) ? res.entry : null;
    } catch (e) {
      return null;
    }
  }

  /** 뜻 목록을 저장용 한 줄로 만든다. */
  function flatten(entry) {
    if (!entry) return '';
    return (entry.ko.length ? entry.ko : entry.en).join(' / ');
  }

  function renderBody(entry) {
    if (!entry) {
      return `<div class="eh-popup-def">정의를 찾을 수 없습니다.</div>`;
    }
    const meta = [entry.pos.join(', '), entry.ipa].filter(Boolean).join(' · ');
    const senses = entry.ko.length ? entry.ko : entry.en;
    const noKo = !entry.ko.length && entry.en.length
      ? `<div class="eh-popup-note">한국어 뜻 없음 — 영어 정의를 보여줍니다</div>` : '';
    return `
      ${meta ? `<div class="eh-popup-phonetic">${esc(meta)}</div>` : ''}
      <div class="eh-popup-divider"></div>
      ${noKo}
      ${senses.map(s => `<div class="eh-popup-def">${esc(s)}</div>`).join('')}
    `;
  }

  async function show({ word, term, sentence, translation, timestamp, x, y }) {
    if (!popupEl) return;

    // 다어절 표현이 있으면 그쪽이 표제어다. find out을 눌렀는데 find가 뜨면
    // 이 기능의 존재 이유가 사라진다 (설계 §9).
    let headword = term || word;

    popupEl.innerHTML = `
      <div class="eh-popup-word">${esc(headword)}</div>
      <div class="eh-popup-loading">불러오는 중...</div>
    `;
    popupEl.classList.add('visible');
    positionPopup(x, y);

    let entry = await lookup(headword);
    render();

    function render() {
      const showWordLink = term && headword === term;
      popupEl.innerHTML = `
        <div class="eh-popup-word">${esc(headword)}</div>
        ${renderBody(entry)}
        ${showWordLink
          ? `<button class="eh-popup-link" id="eh-show-word">"${esc(word)}" 뜻 보기</button>`
          : ''}
        ${sentence ? `<div class="eh-popup-sentence">"${esc(sentence)}"</div>` : ''}
        <div class="eh-popup-actions">
          <button class="eh-popup-btn" id="eh-save-word">${term ? '표현 저장' : '단어 저장'}</button>
          <button class="eh-popup-btn" id="eh-save-sent">문장 저장</button>
        </div>
        <div class="eh-popup-credit">뜻: 위키낱말사전 (CC BY-SA)</div>
      `;
      positionPopup(x, y);
      wire();
    }

    function wire() {
      const link = document.getElementById('eh-show-word');
      if (link) {
        link.addEventListener('click', async (e) => {
          e.stopPropagation();
          headword = word;
          entry = await lookup(word);
          render();
        });
      }

      document.getElementById('eh-save-word').addEventListener('click', () => {
        window.EH.Storage.saveWord({
          word: headword, definition: flatten(entry),
          sentence, translation, timestamp
        }).then((res) => {
          if (window.EH.handleAuthRequired(res)) return;
          window.EH.showToast?.(`✓ "${headword}" 저장됨`);
          document.dispatchEvent(new CustomEvent('eh-item-saved'));
          hide();
        });
      });

      document.getElementById('eh-save-sent').addEventListener('click', () => {
        window.EH.Storage.saveSentence({ original: sentence, translation, timestamp })
          .then((res) => {
            if (window.EH.handleAuthRequired(res)) return;
            window.EH.showToast?.('✓ 문장 저장됨');
            document.dispatchEvent(new CustomEvent('eh-item-saved'));
            hide();
          });
      });
    }
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
