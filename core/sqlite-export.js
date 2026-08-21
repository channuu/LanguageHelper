(function () {
  'use strict';

  /**
   * Builds the .sqlite export bytes from already-fetched words/sentences.
   * Pure — no DOM access, no chrome.* calls — so it's testable with plain Node.
   * @param {object} SQL - the object returned by `await initSqlJs(...)`
   * @param {Array} words
   * @param {Array} sentences
   * @returns {Uint8Array}
   */
  function buildDatabase(SQL, words, sentences) {
    const db = new SQL.Database();

    db.run(`CREATE TABLE words (
      id TEXT PRIMARY KEY,
      word TEXT,
      definition TEXT,
      sentence TEXT,
      translation TEXT,
      platform TEXT,
      content_title TEXT,
      content_id TEXT,
      timestamp REAL,
      saved_at TEXT,
      review_count INTEGER DEFAULT 0,
      next_review_at TEXT
    )`);

    db.run(`CREATE TABLE sentences (
      id TEXT PRIMARY KEY,
      original TEXT,
      translation TEXT,
      platform TEXT,
      content_title TEXT,
      content_id TEXT,
      timestamp REAL,
      saved_at TEXT,
      review_count INTEGER DEFAULT 0,
      next_review_at TEXT
    )`);

    const wordStmt = db.prepare('INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?,?)');
    words.forEach(w => wordStmt.run([
      w.id, w.word, w.definition || '', w.sentence || '', w.translation || '',
      w.platform || '', w.contentTitle || '', w.contentId || '',
      w.timestamp || 0, w.savedAt || '', w.reviewCount || 0, w.nextReviewAt || null
    ]));
    wordStmt.free();

    const sentStmt = db.prepare('INSERT INTO sentences VALUES (?,?,?,?,?,?,?,?,?,?)');
    sentences.forEach(s => sentStmt.run([
      s.id, s.original, s.translation || '', s.platform || '',
      s.contentTitle || '', s.contentId || '', s.timestamp || 0,
      s.savedAt || '', s.reviewCount || 0, s.nextReviewAt || null
    ]));
    sentStmt.free();

    const bytes = db.export();
    db.close();
    return bytes;
  }

  /**
   * Full export flow: init sql.js, build the database, trigger a download.
   * @param {Array} words
   * @param {Array} sentences
   * @param {{locateFile?: (f: string) => string}} [opts]
   */
  async function exportAll(words, sentences, opts = {}) {
    const SQL = await initSqlJs({
      locateFile: opts.locateFile || (f => chrome.runtime.getURL('vendor/' + f))
    });
    const data = buildDatabase(SQL, words, sentences);

    const blob = new Blob([data], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    const today = new Date().toISOString().slice(0, 10);
    a.download = `english_helper_${today}.sqlite`;
    a.click();
    URL.revokeObjectURL(url);
  }

  window.EH = window.EH || {};
  window.EH.SqliteExport = { buildDatabase, exportAll };
})();
