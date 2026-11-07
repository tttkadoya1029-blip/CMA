// スマホ・PCでの表示確認スクリプト
// 使い方: node dev/check-mobile.js   → dev/screens/ に画面ごとのスクリーンショットを保存
// にせSupabase（dev/stub-supabase.js）で全画面を操作し、横はみ出し・JSエラーを検出します。
const {chromium}=require("playwright");
const fs=require("fs"),path=require("path"),http=require("http");
const ROOT=path.join(__dirname,".."),OUT=path.join(__dirname,"screens");
fs.mkdirSync(OUT,{recursive:true});
const VIEWPORTS=[{name:"iphone-se",width:375,height:667},{name:"iphone-15",width:393,height:852},{name:"android-small",width:360,height:740},{name:"pc",width:1280,height:900}];

const server=http.createServer((req,res)=>{
  let p=req.url.split("?")[0];if(p==="/")p="/index.html";
  if(p==="/index.html"){
    let html=fs.readFileSync(path.join(ROOT,"index.html"),"utf8")
      .replace('<script src="config.js"></script>','<script>window.APP_CONFIG={SUPABASE_URL:"https://stub.supabase.co",SUPABASE_ANON_KEY:"stub",ENABLE_GOOGLE:true}</script>')
      .replace(/<script src="https:\/\/cdn\.jsdelivr[^>]*><\/script>/,'<script src="/dev/stub-supabase.js"></script>');
    res.setHeader("content-type","text/html; charset=utf-8");return res.end(html);
  }
  try{res.end(fs.readFileSync(path.join(ROOT,p)))}catch{res.statusCode=404;res.end()}
}).listen(0);
const URL_=`http://localhost:${server.address().port}/`;

(async()=>{
  const browser=await chromium.launch();const problems=[];
  for(const vp of VIEWPORTS){
    for(const role of ["student","teacher"]){
      const ctx=await browser.newContext({viewport:{width:vp.width,height:vp.height},deviceScaleFactor:vp.name==="pc"?1:2,isMobile:vp.name!=="pc",hasTouch:vp.name!=="pc"});
      const page=await ctx.newPage();
      page.on("pageerror",e=>problems.push(`[${vp.name}/${role}] JSエラー: ${e.message}`));
      await page.route(/fonts\.(googleapis|gstatic)\.com/,r=>r.abort());
      const shot=async(label)=>{
        await page.waitForTimeout(250);
        const over=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
        if(over>1)problems.push(`[${vp.name}/${role}] ${label}: 横に ${over}px はみ出しています`);
        await page.screenshot({path:path.join(OUT,`${vp.name}-${role}-${label}.png`),fullPage:true});
      };
      await page.goto(URL_);await page.evaluate(r=>{localStorage.clear();localStorage.setItem("stub_role",r)},role);await page.reload();
      if(role==="student"){await shot("01-login");await page.click("#sw");await page.waitForTimeout(150);await shot("01b-signup");await page.click("#sw");}
      await page.evaluate(()=>localStorage.setItem("stub_logged","1"));await page.reload();await page.waitForTimeout(300);
      if(role==="student"){
        await shot("02a-register");
        await page.fill("#fname","見本 花子");await page.click("#nsub");await page.waitForTimeout(300);
        await shot("02-home");
        await page.click(".who .linkbtn");await page.waitForTimeout(200);await shot("02c-profile-edit");await page.click("#ncancel");await page.waitForTimeout(200);
        await page.fill("#cnum","3");await page.press("#cnum","Enter");await page.locator("#cnum").blur();await page.waitForTimeout(150);
        const label=await page.textContent("#startE");if(!label.includes("3問"))problems.push(`[${vp.name}] 問題数の自由指定が反映されません: ${label}`);
        await shot("02b-home-count");
        await page.click("#startE");await page.waitForTimeout(300);await shot("03-question");
        const qn=await page.textContent(".qno");if(!/\/ 3/.test(qn))problems.push(`[${vp.name}] 出題数が3問になっていません: ${qn}`);
        for(const id of ["#ans-true","#ans-false","#ans-unsure"]){await page.click(id);await page.waitForTimeout(250)}
        await page.waitForTimeout(400);await shot("05-result");
        await page.click('[data-f="wrong"]');await page.waitForTimeout(150);await shot("05b-result-wrong");
        await page.click("#rk");await page.waitForTimeout(300);await shot("06-ranking");
        await page.click('[data-view="home"]');await page.waitForTimeout(200);await page.click('[data-count="all"]').catch(()=>{});await page.click("#startE");await page.waitForTimeout(300);
        await page.click("#ans-true");await page.waitForTimeout(300);await page.click("#stop");await page.waitForTimeout(150);await shot("07-stop-confirm");
        await page.click("#stopYes");await page.waitForTimeout(500);await shot("08-exam-result");
      }else{
        await page.click('[data-view="teacher"]');await page.waitForTimeout(400);await shot("11-teacher");
        await page.click("#smp");await page.waitForTimeout(300);await shot("12-teacher-sample");
        await page.click(".li.click");await page.waitForTimeout(300);await shot("13-student-detail");
      }
      await ctx.close();
    }
  }
  await browser.close();server.close();
  console.log(problems.length?"問題あり:\n"+problems.join("\n"):"OK: 横はみ出し・JSエラーなし");
  console.log("スクリーンショット: "+OUT);
  process.exit(problems.length?1:0);
})();
