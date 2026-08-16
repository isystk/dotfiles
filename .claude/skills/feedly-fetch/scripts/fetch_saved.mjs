import { chromium } from 'playwright';
import { cpSync, mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { homedir } from 'os';

const PROFILE_DIR = process.argv[2] || join(homedir(), '.claude/tools/google-auth/chrome-profile');
const LIMIT = process.argv[3] ? parseInt(process.argv[3], 10) : null;

const tmpProfile = mkdtempSync(join(tmpdir(), 'feedly-profile-'));
cpSync(PROFILE_DIR, tmpProfile, { recursive: true });

let items = [];
try {
  const context = await chromium.launchPersistentContext(tmpProfile, { headless: true });
  const page = await context.newPage();

  const waitForStream = page.waitForResponse(
    (res) => res.url().includes('api.feedly.com') && res.url().includes('/v3/streams/contents'),
    { timeout: 30000 },
  );

  await page.goto('https://feedly.com/i/saved', { waitUntil: 'load', timeout: 30000 });

  let streamJson;
  try {
    const streamRes = await waitForStream;
    streamJson = await streamRes.json();
  } catch (e) {
    await context.close();
    console.error('警告: Feedly内部APIの応答を検知できませんでした（未ログインの可能性）。google-chrome-loginスキルで共有プロファイルにログインし直してください。');
    console.log('[]');
    process.exit(0);
  }

  await context.close();

  items = (streamJson.items || [])
    .map((i) => ({
      id: i.id,
      title: i.title,
      url: i.alternate?.[0]?.href || i.canonicalUrl || null,
      published: i.published ? new Date(i.published).toISOString() : null,
      summary: i.summary?.content || '',
    }));
} finally {
  rmSync(tmpProfile, { recursive: true, force: true });
}

if (LIMIT) {
  items = items.slice(0, LIMIT);
}

console.log(JSON.stringify(items, null, 2));

if (items.length === 0) {
  console.error('警告: 記事0件。google-chrome-loginスキルでPlaywright MCPの共有プロファイル（~/.claude/tools/google-auth/chrome-profile）にログインし直してください。');
}
