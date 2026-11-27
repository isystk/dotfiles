// infographic.html を PNG に書き出す (render.sh から Docker コンテナ内で実行される)
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 10 }, deviceScaleFactor: 2 });
  await page.goto('file:///work/infographic.html');
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `/work/${process.env.OUT_NAME}`, fullPage: true });
  await browser.close();
})();
