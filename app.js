const view=document.querySelector("#view");
let page="board",sort="new",likes=new Set(),voteDone=false,posts=[
 {title:"급식실에 물 마시는 공간을 추가해 주세요",body:"식사 중 물을 마시러 이동하기 불편합니다. 급식실 안에 정수기를 추가하면 좋겠습니다.",category:"시설",likes:24,status:"검토 중",date:"11.26"},
 {title:"점심시간 운동장 이용 시간을 확대해 주세요",body:"점심시간에 운동장을 이용할 수 있는 시간이 조금 더 길었으면 좋겠습니다.",category:"학교생활",likes:18,status:"접수 완료",date:"11.25"},
 {title:"학교 축제에서 학생 공연을 늘려 주세요",body:"학생들이 직접 참여하는 공연 프로그램이 더 많아지면 좋겠습니다.",category:"행사",likes:31,status:"회의 상정",date:"11.24"}
];
const esc=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
function setPage(p){page=p;document.querySelectorAll(".menu-card").forEach(b=>b.classList.toggle("active",b.dataset.page===p));render();window.scrollTo({top:0,behavior:"smooth"})}
document.querySelectorAll("[data-page]").forEach(b=>b.addEventListener("click",()=>setPage(b.dataset.page)));
function head(title,desc="",right=""){return `<div class="section-head"><div><h2>${title}</h2>${desc?`<p class="sub">${desc}</p>`:""}</div>${right}</div>`}
function render(){
 if(page==="board"){
  let items=posts.map((p,i)=>({...p,i}));if(sort==="popular")items.sort((a,b)=>(b.likes+(likes.has(b.i)?1:0))-(a.likes+(likes.has(a.i)?1:0)));
  view.innerHTML=head("학생 건의 게시판","학생들의 다양한 의견을 확인하고 공감해 보세요.",`<select class="select" id="sort"><option value="new">최신순</option><option value="popular" ${sort==="popular"?"selected":""}>인기순</option></select>`)+`<div class="post-list">${items.map(p=>`<article class="post"><div class="post-top"><span class="tag">${esc(p.category)}</span><span class="date">${p.date}</span></div><h3>${esc(p.title)}</h3><p>${esc(p.body)}</p><div class="post-bottom"><span class="status">${esc(p.status)}</span><div class="actions"><button class="btn secondary like" data-like="${p.i}">♡ ${p.likes+(likes.has(p.i)?1:0)}</button><button class="btn ghost detail" data-detail="${p.i}">자세히</button></div></div><div class="detail-text" id="detail-${p.i}" hidden>학생회 진행 상태: ${esc(p.status)} 단계입니다. 검토 후 진행 상황을 안내할 예정입니다.</div></article>`).join("")}</div>`;
  document.querySelector("#sort").onchange=e=>{sort=e.target.value;render()};document.querySelectorAll(".like").forEach(b=>b.onclick=()=>{let i=+b.dataset.like;likes.has(i)?likes.delete(i):likes.add(i);render()});document.querySelectorAll(".detail").forEach(b=>b.onclick=()=>{let el=document.querySelector("#detail-"+b.dataset.detail);el.hidden=!el.hidden});
 }else if(page==="write"){
  view.innerHTML=head("새로운 건의 작성","구체적인 내용과 이유를 함께 작성하면 검토에 도움이 됩니다.")+`<form class="panel" id="write-form"><div class="field-wrap"><label class="label">건의 제목</label><input class="field" name="title" required maxlength="80" placeholder="어떤 점을 개선하고 싶나요?"></div><div class="field-wrap"><label class="label">분야</label><select class="field" name="category"><option>시설</option><option>급식</option><option>학교생활</option><option>행사</option><option>기타</option></select></div><div class="field-wrap"><label class="label">상세 내용</label><textarea name="body" required maxlength="1500" placeholder="현재 상황과 개선이 필요한 이유를 적어 주세요."></textarea><span class="hint">욕설·비방·장난성 글은 등록 대상에서 제외됩니다. 학급회의에서 이미 논의된 안건은 작성하지 말아 주세요.</span></div><button class="btn">건의 제출</button><div id="write-result"></div></form>`;
  document.querySelector("#write-form").onsubmit=e=>{e.preventDefault();let f=new FormData(e.target);posts.unshift({title:f.get("title"),body:f.get("body"),category:f.get("category"),likes:0,status:"접수 완료",date:"방금"});document.querySelector("#write-result").innerHTML='<div class="result">이 기기의 시제품 게시판에 추가했어요. 다른 학생에게는 보이지 않습니다.</div>';e.target.reset()};
 }else if(page==="vote"){
  view.innerHTML=head("진행 중인 투표","투표 화면 시연 · 실제 학생 정보는 입력하지 마세요.")+`<div class="panel"><div><span class="tag">예시 투표</span><h3>다음 체육대회 종목으로 가장 적절한 것은?</h3><p class="sub">예시 항목이며 실제 학교 투표가 아닙니다.</p></div><form id="vote-form"><div class="radio-list">${["피구","줄다리기","계주","기타"].map((x,i)=>`<label class="radio-option"><input type="radio" name="choice" value="${x}" ${i===0?"checked":""}>${x}</label>`).join("")}</div><div class="field-wrap" style="margin-top:15px"><label class="label">제출 전 본인 확인 예시</label><input class="field" placeholder="예: 1111 홍길동" disabled><span class="hint">실제 학번·이름 수집과 중복 투표 검증은 학교 승인 및 안전한 서버 인증을 연결한 뒤 구현합니다.</span></div><button class="btn" disabled style="margin-top:12px">실제 투표 기능 준비 중</button></form></div>`;
 }else if(page==="events"){
  view.innerHTML=head("특별 이벤트","학생 참여 행사와 공모 소식을 확인하세요.")+`<article class="event-card"><span class="tag">참여 예시</span><h3>우리 학교 축제 아이디어 공모</h3><p>학교 축제를 더 재미있게 만들 아이디어를 제안해 주세요.</p><button class="btn secondary" disabled>참여 기능 준비 중</button></article><article class="event-card"><span class="tag">예정</span><h3>학생 참여 프로젝트</h3><p>새로운 이벤트가 등록되면 이곳에서 확인할 수 있습니다.</p></article>`;
 }else if(page==="admin"){
  view.innerHTML=head("관리자 영역","실제 관리자 인증은 서버 연결 후 활성화됩니다.")+`<div class="panel"><div class="field-wrap"><label class="label">관리자 아이디</label><input class="field" placeholder="관리자 계정" disabled></div><div class="field-wrap"><label class="label">비밀번호</label><input class="field" placeholder="비밀번호" type="password" disabled></div><button class="btn" disabled>관리자 로그인 기능 준비 중</button><span class="hint">브라우저 안에 관리자 비밀번호를 저장하는 방식은 안전하지 않아 시제품에서는 로그인 기능을 비활성화했습니다.</span></div>`;
 }
}
render();
if("serviceWorker" in navigator && location.protocol.startsWith("http")) navigator.serviceWorker.register("./sw.js").catch(()=>{});
