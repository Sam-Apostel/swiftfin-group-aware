const { chromium } = require('/opt/node22/lib/node_modules/playwright');
(async()=>{const [,, url,out,w,h,scale]=process.argv;const b=await chromium.launch();const p=await b.newPage({viewport:{width:+w,height:+h},deviceScaleFactor:+(scale||1)});await p.goto(url);await p.waitForTimeout(400);await p.screenshot({path:out,fullPage:true});await b.close();})();
