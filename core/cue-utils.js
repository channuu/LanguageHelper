(function () {
  'use strict';

  // §1h "한 줄에 표시할 분량" — 스크립트 패널(core/script-panel.js)과 영상 위
  // 자막 오버레이(core/subtitle-engine.js + adapters/*.js)가 반드시 같은
  // 문장을 같은 순간에 보여줘야 하므로, 청크 분할 로직을 여기 한 곳에만 둔다.
  //
  // 긴 문장 하나를 자연스러운 끊어읽기 지점(쉼표/세미콜론/대시/등위접속사)
  // 근처에서 여러 개의 짧은 청크로 나눈다. 목표 단어 수로 기계적으로만
  // 자르면 어색한 곳에서 끊기기 쉬워서, 목표치 근처의 "괜찮은 끊는 자리"를
  // 먼저 찾고 없으면 그 자리에서 그냥 자른다.
  // "길게"는 "보통"의 약 1.5~2배 분량을 한 청크로 보여준다(15 × ~1.75 ≈ 26).
  const CHUNK_WORD_BUDGET = { 1: 8, 2: 15, 3: 26 };
  const CHUNK_CONJUNCTIONS = /^(and|but|or|so|because|which|who|that|when|while)$/i;

  function splitIntoChunks(text, cueLines) {
    const budget = CHUNK_WORD_BUDGET[cueLines];
    const words = text.split(/\s+/).filter(Boolean);
    if (!budget || words.length <= budget) return [text];

    const boundaries = [];
    for (let i = 0; i < words.length - 1; i++) {
      const endsWithPunct = /[,;—–:]$/.test(words[i]);
      const nextIsConj = CHUNK_CONJUNCTIONS.test(words[i + 1].replace(/[^a-zA-Z]/g, ''));
      if (endsWithPunct || nextIsConj) boundaries.push(i + 1);
    }

    const tolerance = Math.max(2, Math.floor(budget / 2));
    const chunks = [];
    let start = 0;
    while (start < words.length) {
      const target = start + budget;
      if (target >= words.length) {
        chunks.push(words.slice(start).join(' '));
        break;
      }
      let best = null, bestDist = Infinity;
      for (const b of boundaries) {
        if (b <= start) continue;
        const dist = Math.abs(b - target);
        if (dist <= tolerance && dist < bestDist) { best = b; bestDist = dist; }
      }
      const cut = best || target;
      chunks.push(words.slice(start, cut).join(' '));
      start = cut;
    }
    return chunks;
  }

  // cue 하나를 chunk들로 나누고, 각 chunk의 단어 수 비율만큼 cue의 [start,end]
  // 구간을 나눠 chunk별 시작/끝 시각을 근사한다. 스크립트 패널의 행 생성과
  // 오버레이의 실시간 표시가 반드시 같은 시간 경계를 써야 "동일한 스크립트"로
  // 보인다.
  function getChunksWithTiming(cue, cueLines) {
    const chunks = splitIntoChunks(cue.text, cueLines);
    const dur = cue.end - cue.start;
    const totalWords = chunks.reduce((n, c) => n + c.split(/\s+/).length, 0) || 1;
    let wordsSoFar = 0;
    return chunks.map((chunkText, ci) => {
      const chunkStart = cue.start + dur * (wordsSoFar / totalWords);
      wordsSoFar += chunkText.split(/\s+/).length;
      const chunkEnd = cue.start + dur * (wordsSoFar / totalWords);
      return { text: chunkText, start: chunkStart, end: chunkEnd, isFirst: ci === 0, isLast: ci === chunks.length - 1 };
    });
  }

  // 시각 t(이미 cue.start~cue.end 범위 안이라고 가정)에 해당하는 청크를
  // 돌려준다. 오버레이의 RAF 틱에서 매 프레임 호출된다. index/total은
  // 호출부가 번역 문장도 같은 개수로 나눠(splitIntoNChunks) 같은 위치의
  // 조각을 골라 쓸 수 있게 하기 위함이다.
  function getChunkAtTime(cue, t, cueLines) {
    const chunks = getChunksWithTiming(cue, cueLines);
    const found = chunks.find(c => t >= c.start && t <= c.end) || chunks[chunks.length - 1];
    return { ...found, index: chunks.indexOf(found), total: chunks.length };
  }

  // referenceCue(보통 영어 cue)와 같은 문장을 가리키는 cue를 시작 시각
  // 근접도로 찾는다. 넷플릭스/유튜브 모두 언어별로 자막 파일을 따로 만드는데,
  // 번역 자막의 끝나는 시각이 원본보다 짧게 잡힌 경우가 흔하다 — en/native를
  // 각자 자기 cue의 [start,end]로 독립적으로 시간 매칭하면, 번역이 먼저
  // 사라지고 원본만 잠깐 혼자 남아 있는 것처럼 보인다("영어 자막만 계속/다시
  // 표시되는 것 같다"는 증상의 실제 원인). 시작 시각으로 짝을 찾은 뒤에는
  // 그 native cue 자신의 end와 무관하게 referenceCue가 떠 있는 동안 계속
  // 같이 보여줘서 둘이 항상 함께 나타났다 함께 사라지게 한다.
  function findPairedCue(cues, referenceCue, toleranceSec) {
    toleranceSec = toleranceSec == null ? 1.0 : toleranceSec;
    // 넷플릭스는 언어별로 줄을 나누는 기준(세그멘테이션) 자체가 달라서,
    // 번역 cue 하나가 영어 cue 여러 개를 한꺼번에 담당하는 경우가 흔하다
    // (예: 영어는 "He said..."/"on him"/"when they..." 세 줄인데 번역은
    // 그걸 합친 한 문장 하나). 이때 뒤쪽 영어 조각들의 시작 시각은 그
    // 번역 cue "자신의" 시작 시각과는 멀어도, 그 cue의 [start,end] 구간
    // 안에는 들어간다 — start 근접도보다 먼저, "지금 이 영어 cue가 시작한
    // 시점에 이미 재생 중이던" 번역 cue가 있는지부터 확인해야 이런 경우도
    // 놓치지 않는다.
    for (const c of cues) {
      if (referenceCue.start >= c.start && referenceCue.start <= c.end) return c;
    }
    let best = null, bestDist = Infinity;
    for (const c of cues) {
      const dist = Math.abs(c.start - referenceCue.start);
      if (dist < bestDist) { bestDist = dist; best = c; }
    }
    return (best && bestDist <= toleranceSec) ? best : null;
  }

  // 영어 문장이 청크 n개로 나뉘면, 번역 문장도 그 n개에 맞춰 대략 균등하게
  // 나눈다. 원문과 번역은 어순이 달라 단어 단위로 정확히 대응되진 않지만,
  // 청크마다 번역 전체를 통째로 반복하는 것보다는 "그 청크만큼의 분량"을
  // 보여주는 쪽이 스크립트 패널/오버레이가 청크 수준으로 정말 맞물려
  // 움직인다는 느낌을 준다. 항상 정확히 n개를 반환한다(문서량 문장이
  // n보다 짧으면 뒤쪽 일부는 빈 문자열).
  function splitIntoNChunks(text, n) {
    if (n <= 1) return [text];
    const words = text.split(/\s+/).filter(Boolean);
    const chunks = [];
    const base = Math.floor(words.length / n);
    let extra = words.length % n;
    let idx = 0;
    for (let i = 0; i < n; i++) {
      const size = base + (extra > 0 ? 1 : 0);
      if (extra > 0) extra--;
      chunks.push(words.slice(idx, idx + size).join(' '));
      idx += size;
    }
    return chunks;
  }

  window.EH = window.EH || {};
  window.EH.CueUtils = { splitIntoChunks, getChunksWithTiming, getChunkAtTime, findPairedCue, splitIntoNChunks };
})();
