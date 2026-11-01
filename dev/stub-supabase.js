// 画面確認用の「にせSupabase」。本番では使いません（dev/check-mobile.js からだけ読み込みます）。
// localStorage の stub_role=teacher|student / stub_logged=1 で状態を切り替えます。
(function(){
const P={"1002":"株式会社の基本原理と株式の機能","1003":"株式の種類と特徴","1006":"株価指数","1018":"産業の戦略的分析","1024":"利益予想と株式価値評価"};
const points=Object.entries(P).map(([code,title],i)=>({code,chapter:1,title,unit_key:"I-1",description:title+"について理解する。",video_url:code==="1006"?"https://www.youtube.com/watch?v=example":null,sort:i}));
const Q=[["q01","1002","基礎",true],["q02","1003","基礎",false],["q03","1006","標準",true],["q04","1018","標準",false],["q05","1024","応用",false]]
  .map((x,i)=>({id:x[0],point_code:x[1],level:x[2],stem:"テスト用の問題文です。証券アナリスト試験の正誤問題を想定した、少し長めの文章でスマホでの折り返しを確認します（"+x[0]+"）。",answer:x[3],explanation:"テスト用の解説 "+x[0],sort:i}));
const role=localStorage.getItem("stub_role")||"student";
const now=Date.now(),iso=t=>new Date(t).toISOString();
const db={
  profiles:[{id:"u1",email:"me@example.com",display_name:"テストユーザー（とても長い名前の人）",role,show_in_ranking:true,created_at:1},
            {id:"u2",email:"b@example.com",display_name:"受講者B",role:"student",show_in_ranking:true,created_at:2}],
  attempts:[["q01",true,12000],["q02",false,9000],["q03",false,40000],["q04",true,15000]].map((a,i)=>({id:i+1,user_id:"u2",session_id:"sB",question_id:a[0],choice:true,is_correct:a[1],time_ms:a[2],answered_at:iso(now-86400000),sessions:{mode:"practice"}})),
  sessions:[],questions:Q,points
};
let n=10;
function qb(t){let f=[],op="select",payload=null;const rows=()=>db[t].filter(r=>f.every(g=>g(r)));const api={
  select(){return api},order(){return api},eq(k,v){f.push(r=>r[k]===v);return api},
  range(a,b){return Promise.resolve({data:rows().slice(a,b+1),error:null})},
  maybeSingle(){return Promise.resolve({data:rows()[0]||null,error:null})},
  single(){if(op==="insert"){const r={id:"sess"+(n++),...payload};db[t].push(r);return Promise.resolve({data:r,error:null})}return api.maybeSingle()},
  insert(p){op="insert";payload=p;return api},update(p){op="update";payload=p;return api},
  then(res){if(op==="update")rows().forEach(r=>Object.assign(r,payload));res({data:rows(),error:null})}};return api}
function stats(key){const g={};db.attempts.forEach(a=>{const k=key(a);(g[k]=g[k]||[]).push(a)});
  return Object.entries(g).map(([k,a])=>{const t=a.map(x=>x.time_ms).sort((x,y)=>x-y);return {k,n:a.length,accuracy:a.filter(x=>x.is_correct).length/a.length,median_ms:t[t.length>>1]}})}
window.supabase={createClient:()=>({
  auth:{getSession:async()=>({data:{session:localStorage.getItem("stub_logged")?{user:{id:"u1",email:"me@example.com"}}:null}}),onAuthStateChange(){},
    signInWithPassword:async()=>{localStorage.setItem("stub_logged","1");location.reload();return {data:{},error:null}},
    signOut:async()=>{localStorage.removeItem("stub_logged");location.reload()},signUp:async()=>({data:{session:null},error:null}),signInWithOAuth:async()=>({error:null})},
  from:qb,
  rpc:async(name,a)=>{
    if(name==="get_questions")return {data:Q.map(({answer,explanation,...r})=>r),error:null};
    if(name==="get_question_stats")return {data:stats(x=>x.question_id).map(s=>({question_id:s.k,...s})),error:null};
    if(name==="get_point_stats")return {data:stats(x=>Q.find(q=>q.id===x.question_id).point_code).map(s=>({point_code:s.k,...s})),error:null};
    if(name==="get_exam_ranking")return {data:[{rank:1,display_name:"受講者B",correct:5,total:5,total_ms:61000,median_ms:12000,is_me:false},{rank:2,display_name:"テストユーザー（とても長い名前の人）",correct:4,total:5,total_ms:52000,median_ms:9800,is_me:true}],error:null};
    if(name==="get_activity_ranking")return {data:[{rank:1,display_name:"受講者B",answers:40,sessions:8,is_me:false},{rank:2,display_name:"テストユーザー（とても長い名前の人）",answers:12,sessions:3,is_me:true}],error:null};
    if(name==="submit_answer"){const q=Q.find(x=>x.id===a.p_question),ok=a.p_choice===q.answer;
      db.attempts.push({id:db.attempts.length+1,user_id:"u1",session_id:a.p_session,question_id:q.id,choice:a.p_choice,is_correct:ok,time_ms:a.p_time_ms,answered_at:iso(Date.now()),sessions:{mode:"practice"}});
      return {data:[{is_correct:ok,answer:q.answer,explanation:q.explanation}],error:null}}
    return {data:null,error:{message:"unknown rpc "+name}};
  }
})};
})();
