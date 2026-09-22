// Guest-only regression: local favorites must not refetch on every render.
// Run against a forum with food_public_browse enabled and at least one shop.
const assert = require('node:assert/strict');
const { chromium } = require(process.env.RIVER_PLAYWRIGHT || 'playwright');
(async () => {
  const base = process.env.RIVER_BASE_URL;
  assert(base, 'Set RIVER_BASE_URL to the forum to verify');
  const browser = await chromium.launch({ executablePath: process.env.RIVER_CHROMIUM, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    let reads = 0;
    await page.route('**/food/action', () => { throw Error('Guest test must not write to server'); });
    await page.route('**/food/state.json*', async route => {
      if (new URL(route.request().url()).searchParams.get('view') === 'favorites') {
        reads++;
        if (reads > 5) { await route.fulfill({status:429,body:'Test stopped repeated requests'}); return; }
      }
      await route.continue();
    });
    await page.goto(base + '/food');
    const favorite = page.locator('.food-favorite').first();
    await favorite.waitFor(); await favorite.click();
    await page.locator('.food-nav').getByRole('link', {name:'收藏',exact:true}).click();
    await page.locator('.food-shop').first().waitFor();
    await page.waitForTimeout(1000);
    assert.equal(reads,1,'Switching to favorites makes one request');
    reads = 0;
    await page.goto(base + '/food?view=favorites');
    await page.locator('.food-shop').first().waitFor();
    await page.waitForTimeout(1000);
    assert.equal(reads,2,'Direct bookmarks load the route then hydrate local IDs once');
    assert.equal(await page.locator('.food-shop').count(),1);
    console.log('PASS guest favorites: tab navigation and direct bookmark do not loop');
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
