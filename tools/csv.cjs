'use strict';
// RFC 4180 CSV parser shared by the DBC2CSV import tools (strict quoting, CRLF/LF, BOM tolerant).
function parseCSV(text) {
  text = text.replace(/^\uFEFF/, '');
  const rows = [];
  let row = [], field = '', quoted = false, closed = false;
  function finishField() { row.push(field); field = ''; closed = false; }
  function finishRow() { finishField(); rows.push(row); row = []; }
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (quoted) {
      if (char === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else { quoted = false; closed = true; }
      } else field += char;
    } else if (char === '"' && field === '' && !closed) {
      quoted = true;
    } else if (char === ',') {
      finishField();
    } else if (char === '\r' || char === '\n') {
      if (char === '\r' && text[i + 1] === '\n') i++;
      finishRow();
    } else {
      if (char === '"' || closed) throw new Error('Malformed CSV quoting.');
      field += char;
    }
  }
  if (quoted) throw new Error('Unterminated CSV quoted field.');
  if (field !== '' || closed || row.length) finishRow();
  return rows;
}


module.exports = { parseCSV };
