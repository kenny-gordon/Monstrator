const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const TYPES = { Npc: 'npc', Item: 'item', Quest: 'quest', Object: 'object' };
const FIELDS = {
  Npc: ['name', 'minLevel', 'maxLevel'],
  Item: ['name', 'itemLevel', 'requiredLevel'],
  Quest: ['name', 'questLevel', 'requiredLevel'],
  Object: ['name'],
};

function identity(url) {
  const parsed = new URL(url);
  if (parsed.protocol !== 'https:' || parsed.hostname !== 'www.wowhead.com' || parsed.username || parsed.password || parsed.port) {
    throw new Error('Reference must use https://www.wowhead.com');
  }
  const match = parsed.pathname.match(/^\/(classic|tbc|wotlk)\/(npc|item|quest|object)=(\d+)(?:\/[^/]*)?$/);
  if (!match || parsed.search || parsed.hash || !Number.isSafeInteger(Number(match[3])) || Number(match[3]) <= 0) {
    throw new Error('Reference must identify a version-labelled English Wowhead entity page');
  }
  return { edition: match[1], kind: Object.keys(TYPES).find((kind) => TYPES[kind] === match[2]), id: Number(match[3]) };
}

function decodeEntities(text) {
  return text.replace(/&(#x[0-9a-f]+|#\d+|amp|quot|apos|lt|gt|nbsp);/gi, (whole, entity) => {
    if (entity[0] === '#') {
      const value = entity[1].toLowerCase() === 'x' ? parseInt(entity.slice(2), 16) : Number(entity.slice(1));
      if (value < 0 || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) return whole;
      return String.fromCodePoint(value);
    }
    return { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>', nbsp: ' ' }[entity.toLowerCase()];
  });
}

function attributes(tag) {
  const result = {};
  for (const match of tag.matchAll(/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) {
    result[match[1].toLowerCase()] = decodeEntities(match[2] ?? match[3]);
  }
  return result;
}

// Only read head metadata; script/comment text must not impersonate entity tags.
function parseHTML(html, expected) {
  const clean = html.replace(/<!--[\s\S]*?-->/g, '').replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, '');
  const head = clean.match(/<head\b[^>]*>([\s\S]*?)<\/head\s*>/i)?.[1];
  if (!head) return { status: 'unavailable', reason: 'No complete HTML head; possible blocked/incomplete page' };
  const canonicalTag = [...head.matchAll(/<link\b[^>]*>/gi)].map((match) => attributes(match[0]))
    .find((attrs) => attrs.rel && attrs.rel.toLowerCase() === 'canonical');
  if (!canonicalTag || !canonicalTag.href) return { status: 'unavailable', reason: 'No canonical entity URL; possible blocked/incomplete page' };
  let actual;
  try { actual = identity(canonicalTag.href); }
  catch { return { status: 'unavailable', reason: 'Canonical URL is not a supported entity page' }; }
  if (actual.id !== expected.id || actual.kind !== expected.kind || actual.edition !== expected.edition) {
    return { status: 'unavailable', reason: 'Canonical entity identity/version differs from the requested record' };
  }
  const title = head.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i);
  const editionTitle = { classic: 'Classic World of Warcraft', tbc: 'TBC Classic', wotlk: 'WotLK Classic' }[expected.edition];
  const suffix = new RegExp(`^(.+?) - ${expected.kind === 'Npc' ? 'NPC' : expected.kind} - ${editionTitle}$`);
  const name = title && decodeEntities(title[1].trim()).match(suffix);
  if (!name) return { status: 'unavailable', reason: 'No recognizable entity title; possible challenge/error page' };
  const metadata = [...head.matchAll(/<meta\b[^>]*>/gi)].map((match) => attributes(match[0]));
  const description = metadata.find((attrs) => attrs.name && attrs.name.toLowerCase() === 'description')?.content || '';
  const facts = { name: name[1] }, evidence = { name: 'page title' };
  if (expected.kind === 'Npc') {
    const prefix = name[1] + ' is a level ';
    if (description.startsWith(prefix)) {
      const levels = description.slice(prefix.length).match(/^(\d+)(?:\s*-\s*(\d+))?\s+(?:(?:Rare Elite|Rare|Elite|Boss)\s+)?NPC\b/);
      if (levels) {
        facts.minLevel = Number(levels[1]);
        facts.maxLevel = Number(levels[2] || levels[1]);
        if (facts.minLevel > facts.maxLevel || !Number.isSafeInteger(facts.maxLevel)) {
          return { status: 'unavailable', reason: 'Invalid metadata level range' };
        }
        evidence.minLevel = evidence.maxLevel = 'page metadata';
      }
    }
  }
  if (expected.kind === 'Item') {
    const level = description.match(/\bhas an item level of (\d+)\b/i);
    if (level) {
      facts.itemLevel = Number(level[1]); evidence.itemLevel = 'page metadata';
      if (!Number.isSafeInteger(facts.itemLevel)) return { status: 'unavailable', reason: 'Invalid item level metadata' };
    }
  }
  return { status: 'readable', facts, evidence, canonicalURL: canonicalTag.href };
}

function loadReferences(file) {
  const manifest = JSON.parse(fs.readFileSync(file, 'utf8')), references = [], seen = new Set();
  if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.entries)) throw new Error('Expected schemaVersion 1 and entries array');
  const folder = fs.realpathSync(path.dirname(file));
  for (const entry of manifest.entries) {
    const expected = identity(entry.url), key = `${expected.kind}:${expected.id}:${expected.edition}`;
    if (entry.kind !== expected.kind || entry.id !== expected.id || seen.has(key)) {
      throw new Error('Mismatched or duplicate reference: ' + entry.url);
    }
    const date = typeof entry.checkedAt === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(entry.checkedAt)
      ? new Date(entry.checkedAt) : new Date(NaN);
    if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== entry.checkedAt) {
      throw new Error('Reference requires valid checkedAt date: ' + entry.url);
    }
    seen.add(key);
    let parsed, sha256, snapshotFile;
    if (entry.file) {
      if (entry.facts) throw new Error('Choose a saved HTML file or reviewed facts, not both');
      const full = fs.realpathSync(path.resolve(folder, entry.file));
      const relative = path.relative(folder, full);
      if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) {
        throw new Error('Snapshot must be inside the manifest folder');
      }
      snapshotFile = full;
      const html = fs.readFileSync(full, 'utf8');
      sha256 = crypto.createHash('sha256').update(html).digest('hex');
      parsed = parseHTML(html, expected);
    } else if (entry.facts && typeof entry.facts === 'object' && !Array.isArray(entry.facts)) {
      const fields = Object.keys(entry.facts);
      if (!fields.length || fields.some((field) => !FIELDS[expected.kind].includes(field))) throw new Error('Unsupported or empty fact fields');
      for (const field of fields) {
        const value = entry.facts[field];
        if ((field === 'name' && (typeof value !== 'string' || !value.trim()))
          || (field !== 'name' && (!Number.isSafeInteger(value) || value < 0))) throw new Error('Invalid fact: ' + field);
        if (!entry.evidence || typeof entry.evidence[field] !== 'string' || !entry.evidence[field].trim()) {
          throw new Error('Every reviewed fact needs field-level evidence');
        }
        if (entry.facts.minLevel !== undefined && entry.facts.maxLevel !== undefined
          && entry.facts.minLevel > entry.facts.maxLevel) throw new Error('Invalid fact level range');
      }
      parsed = { status: 'readable', facts: entry.facts, evidence: entry.evidence };
    } else throw new Error('Reference needs a saved HTML file or reviewed facts: ' + entry.url);
    references.push({ ...expected, url: entry.url, checkedAt: entry.checkedAt, sha256, snapshotFile, ...parsed });
  }
  return references;
}

function compareReferences(tables, references) {
  const { decodeRow } = require('./monstrator-db.cjs');
  const results = [], checked = new Set();
  const summary = { references: references.length, matched: 0, conflicts: 0, unavailable: 0,
    versionMismatch: 0, missingLocal: 0, comparedFields: 0 };
  for (const ref of references) {
    const result = { kind: ref.kind, id: ref.id, url: ref.url, checkedAt: ref.checkedAt,
      sha256: ref.sha256, snapshotFile: ref.snapshotFile, fields: [] };
    if (ref.status !== 'readable') {
      result.status = 'unavailable'; result.reason = ref.reason; summary.unavailable++;
    } else if (ref.edition !== 'classic') {
      result.status = 'version-mismatch'; result.reason = 'Non-Classic reference does not establish Forever facts'; summary.versionMismatch++;
    } else if (!tables[ref.kind]?.has(ref.id)) {
      result.status = 'missing-local'; result.reason = 'Published reference is not present locally; review before adding'; summary.missingLocal++;
    } else {
      const row = decodeRow(ref.kind, tables[ref.kind].get(ref.id));
      for (const [field, value] of Object.entries(ref.facts)) {
        result.fields.push({ field, local: row[field] ?? null, reference: value, matches: row[field] === value,
          evidence: ref.evidence[field] });
      }
      result.status = result.fields.every((field) => field.matches) ? 'matched-fields' : 'conflict';
      summary[result.status === 'conflict' ? 'conflicts' : 'matched']++;
      summary.comparedFields += result.fields.length;
      checked.add(`${ref.kind}:${ref.id}`);
    }
    results.push(result);
  }
  const coverage = {};
  for (const kind of Object.keys(TYPES)) {
    const total = tables[kind]?.size || 0;
    const count = [...checked].filter((key) => key.startsWith(kind + ':')).length;
    coverage[kind] = { total, checkedRecords: count, uncheckedRecords: total - count };
  }
  return { scope: 'Only supplied factual fields are compared; no network requests, pruning, placement or drop-table validation.',
    summary, coverage, results };
}

function queueReferences(tables, references) {
  const covered = new Set(references.filter((ref) => ref.status === 'readable' && ref.edition === 'classic')
    .map((ref) => `${ref.kind}:${ref.id}`));
  return Object.keys(TYPES).flatMap((kind) => [...(tables[kind]?.keys() || [])].sort((a, b) => a - b)
    .filter((id) => !covered.has(`${kind}:${id}`))
    .map((id) => ({ kind, id, url: `https://www.wowhead.com/classic/${TYPES[kind]}=${id}` })));
}

module.exports = { identity, parseHTML, loadReferences, compareReferences, queueReferences };
