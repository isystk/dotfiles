#!/usr/bin/env python3
import asyncio
import sys
from playwright.async_api import async_playwright

async def capture_page(browser, url, index):
    page = await browser.new_page()
    try:
        await page.goto(url, wait_until="networkidle")
        path = f"screenshot_{index}.png"
        await page.screenshot(path=path, full_page=True)
        print(f"Captured: {url} -> {path}")
    except Exception as e:
        print(f"Failed to capture {url}: {e}")
    finally:
        await page.close()

async def main(url_list):
    if not url_list:
        print("Usage: ./web_screenshot.py <URL1> <URL2> ...")
        return

    async with async_playwright() as p:
        browser = await p.chromium.launch()
        # 並列でタスクを実行
        tasks = [capture_page(browser, url, i) for i, url in enumerate(url_list)]
        await asyncio.gather(*tasks)
        await browser.close()

if __name__ == "__main__":
    # 最初の引数はスクリプト名なので、2番目以降を取得
    urls = sys.argv[1:]
    asyncio.run(main(urls))