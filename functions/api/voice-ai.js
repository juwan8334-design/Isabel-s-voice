const base='https://fsalybetyybqgtnjvsfi.supabase.co';
const key='sb_publishable_5vGNWo_tAVVRpKBnXSiJcw_B30yW1es';
const tasks=['건의 요약 및 분류','유사 건의 그룹화','우선순위 추천','공식 답변 초안','대의원회 회의 자료','주간 활동 보고서','서비스 문의 분석'];
const sample='가상 자료: A. 도서관 좌석 안내 표지 추가 요청(공감 12). B. 도서관 빈 좌석 확인 방법 안내 요청(공감 8). C. 체육대회 종목 의견 조사 요청(공감 20). D. 행사 일정 안내 화면 글씨가 작다는 문의 2건. 모든 안건은 미검토 상태이며 실제 학교 자료가 아니다.';
const out=(status,data)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}});
export async function onRequestPost({request,env}){
 try {
  if(request.headers.get('Origin')!=='https://isabels-voice.pages.dev')return out(403,{error:'허용되지 않은 주소'});
  const auth=request.headers.get('Authorization'); if(!auth?.startsWith('Bearer '))return out(401,{error:'로그인 필요'});
  const headers={apikey:key,Authorization:auth,'Content-Type':'application/json'};
  const rpc=async name=>{const r=await fetch(base+'/rest/v1/rpc/'+name,{method:'POST',headers,body:'{}'});return r.ok&&await r.json()===true;};
  if(!await rpc('is_admin'))return out(403,{error:'관리자 인증 실패'});
  const raw=await request.text(); if(raw.length>200)return out(400,{error:'잘못된 요청'});
  const body=JSON.parse(raw); if(!Number.isInteger(body.task)||!tasks[body.task]||Object.keys(body).length!==1)return out(400,{error:'잘못된 작업'});
  if(!env.AI)return out(503,{error:'AI 바인딩 없음'});
  if(!await rpc('voice_ai_reserve'))return out(429,{error:'일일 시험 호출 한도 또는 서버 권한 오류'});
  const result=await env.AI.run('@cf/meta/llama-3.3-70b-instruct-fp8-fast',{messages:[{role:'system',content:'한국어로 간결하게 작성하는 학생회 업무 보조 도구입니다. 가상 자료만 사용하고 실제 사실이나 처리 완료를 꾸며내지 마세요. 결과는 검토용 초안입니다.'},{role:'user',content:tasks[body.task]+' 작업을 수행하세요. '+sample}],max_tokens:650});
  if(typeof result?.response!=='string')return out(502,{error:'AI 응답 형식 오류'});
  return out(200,{result:result.response});
 }catch{return out(503,{error:'AI 호출 실패. 설정 또는 무료 한도를 확인하세요.'});}
}
export function onRequestGet(){return out(405,{error:'POST만 허용'});}
