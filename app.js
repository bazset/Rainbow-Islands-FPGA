(()=>{
"use strict";
const DATA=window.PCB_PUBLIC_DATA, JA=window.PCB_JA;
const EN={
 title:"Rainbow Islands PCB Explorer",
 intro:"Explore the original Taito Rainbow Islands arcade board, its chips, circuits and MiSTer FPGA equivalents.",
 language:"Language",readOnly:"Read-only research explorer",boardRevision:"Extra schematics: different PCB revision",
 mobileHint:"Tap a highlighted chip or a name below to see its information instantly.",closeDetails:"Close chip details",
 board:"Original PCB photographs",front:"Component side",back:"Solder side",zoom:"Zoom",
 search:"Search components, signals, files…",all:"All categories",
 legend:"Solid markers = marked components. Dashed markers = estimated regions. Back-side nets are not electrically verified.",
 photoCredit:"PCB photographs generously provided by Ben. Thank you, Ben!",
 compare:"Compare 2008 photo",compareBen:"Ben’s PCB photo — our mapped board reference",compareCommons:"Noggin73’s 2008 Wikimedia Commons photo (public domain). Tap to enlarge.",
 archiveFacts:"Historical photo: Noggin73; uploaded 24 January 2008; 1,280 × 848 pixels; public domain.",
 photoDiff:"The 2008 photograph appears to have a small daughterboard at the upper right. This does not establish the same board revision, ROM population, chip positions or wiring as Ben’s board.",
 commonsSource:"Original Wikimedia Commons photo and licence ↗",
 circuits:"Circuit references",references:"Reference sources",
 footer:"BAZSET hardware research · Partial original-board drawings and separately identified donor schematics; not a complete verified netlist.",
 noResults:"No matching items found.",about:"Function",addr:"Memory / I/O address",focus:"Research priority",
 source:"Relevant FPGA source modules (names only)",evidence:"Location confidence",
 confirmed:"Visibly marked component",romLabel:"Visible ROM label",approx:"Estimated area: precise location not verified",
 related:"Relevant circuit references",hardware:"Hardware devices",check:"What to check in the FPGA",
 caution:"Evidence and caveats",original:"Original B22 circuit references",donor:"Different-board schematic reference",
 read:"Open reference ↗",noFull:"No complete, verified K1100277A schematic has been located.",
 present:"Showing",chipCount:"components / regions",circuitSource:"Source reference",
 backInfo:"No component overlays appear on the solder-side photo because the copper nets are not electrically verified.",
 noteRTL:"This public version shows module names only. Private or in-development source code is not published here.",
 types:{"CPU":"CPU","Graphics":"Graphics","Audio":"Audio","ROM":"ROM","Memory":"Memory","Control":"Control","Video":"Video","I/O":"I/O","Timing":"Timing"},
 statuses:{"B22 partial traced":"B22 partial traced circuit","B22 contextual / partial":"B22 contextual / partial","B22 source + repair observation":"B22 repair observation","Cross-board donor only":"Donor board only","Different board revision / reference only":"Different board revision"}
};
const $=id=>document.getElementById(id);
if(!DATA||!JA){document.body.textContent="Dashboard files are incomplete.";return;}
const escape=s=>String(s??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&#39;");
const link=(url,label)=>'<a target="_blank" rel="noopener noreferrer" href="'+escape(url)+'">'+escape(label)+'</a>';
const tags=s=>'<span class="tag">'+escape(s)+'</span>';
let lang=new URLSearchParams(window.location.search).get("lang") || (()=>{
 try{return localStorage.getItem("ri_pcb_language")||"en"}catch{return "en"}
})();
if(!["en","ja"].includes(lang))lang="en";
const mobileZoom=Math.max(35,Math.min(100,Math.floor((window.innerWidth-45)/716*100/5)*5));
const state={side:"front",scale:mobileZoom,search:"",cat:"all",selected:{type:"node",id:"tile"}};
const t=k=>(lang==="ja"?JA.ui:EN)[k] ?? EN[k] ?? k;
const tr=(kind,id,field,defaultValue)=>{
 if(lang!=="ja")return defaultValue;
 return JA[kind]?.[id]?.[field] ?? defaultValue;
};
const mobileSheet=window.matchMedia("(max-width:920px)");
let lastTrigger=null;
function openSheet(){
 if(!mobileSheet.matches)return;
 $("detailPanel").setAttribute("role","dialog");
 $("detailPanel").setAttribute("aria-modal","true");
 $("detailPanel").setAttribute("aria-labelledby","detailTitle");
 $("detailPanel").scrollTop=0;
 document.body.classList.add("sheet-open");
 $("closeDetail").focus({preventScroll:true});
}
function closeSheet(restoreFocus=true){
 if(!document.body.classList.contains("sheet-open"))return;
 document.body.classList.remove("sheet-open");
 $("detailPanel").removeAttribute("role");
 $("detailPanel").removeAttribute("aria-modal");
 $("detailPanel").removeAttribute("aria-labelledby");
 if(restoreFocus){
  if(lastTrigger&&lastTrigger.isConnected)lastTrigger.focus({preventScroll:true});
  else $("frontBtn").focus({preventScroll:true});
 }
}
const menu=e=>{
 e.preventDefault();
 lastTrigger=e.currentTarget;
 state.selected={type:e.currentTarget.dataset.kind,id:e.currentTarget.dataset.id};
 renderDetail();renderMap();openSheet();
};
function sourceCards(arr){
 if(!arr?.length)return "";
 return '<div class="tags">'+arr.map(f=>tags(f)).join(" ")+'</div><p class="small">'+escape(t("noteRTL"))+'</p>';
}
function setLanguage(){
 document.documentElement.lang=lang;
 $("language").value=lang;
 document.querySelectorAll("[data-t]").forEach(el=>el.textContent=t(el.dataset.t));
 $("search").placeholder=t("search");
 $("search").setAttribute("aria-label",t("search"));
 $("category").setAttribute("aria-label",t("all"));
 $("closeDetail").setAttribute("aria-label",t("closeDetails"));
 $("closeDetail").title=t("closeDetails");
 renderCats();renderLists();renderDetail();renderMap();
}
function renderCats(){
 const current=state.cat;
 $("category").innerHTML='<option value="all">'+escape(t("all"))+'</option>'+
 [...new Set(DATA.nodes.map(n=>n.category))].sort().map(c=>'<option value="'+escape(c)+'">'+escape(t("types")[c]||c)+'</option>').join("");
 $("category").value=current;
}
function renderLists(){
 const q=state.search.toLocaleLowerCase();
 const relevant=n=>(state.cat==="all"||n.category===state.cat)&&
 [n.id,n.name,n.role,n.category,n.address,n.priority,...n.rtl,tr("nodes",n.id,"name",""),tr("nodes",n.id,"role","")].join(" ").toLocaleLowerCase().includes(q);
 const chips=DATA.nodes.filter(relevant);
 $("chips").innerHTML=chips.length?chips.map(n=>'<button data-kind="node" data-id="'+escape(n.id)+'">'+escape(tr("nodes",n.id,"name",n.name))+'</button>').join(""):'<span class="small">'+escape(t("noResults"))+'</span>';
 const circuits=DATA.circuits.filter(n=>[n.title,n.summary,n.id,...n.rtl,tr("circuits",n.id,"title","")].join(" ").toLocaleLowerCase().includes(q));
 $("circuits").innerHTML=circuits.length?circuits.map(c=>'<button data-kind="circuit" data-id="'+escape(c.id)+'">'+escape(tr("circuits",c.id,"title",c.title))+'</button>').join(""):'<span class="small">'+escape(t("noResults"))+'</span>';
 document.querySelectorAll("#chips button,#circuits button").forEach(b=>b.addEventListener("click",menu));
 return chips;
}
function renderMap(){
 const comparison=state.side==="compare";
 $("boardImage").hidden=comparison;
 $("compareView").hidden=!comparison;
 $("comparisonNotes").hidden=!comparison;
 $("zoom").disabled=comparison;
 $("zoom").title=comparison?(lang==="ja"?"比較画像では拡大率を変更できません":"Zoom applies to Ben’s mapped PCB views only"):"";
 if(comparison)return;
 const board=$("boardImage");
 board.style.width=(716*state.scale/100)+"px";
 board.style.height=(711*state.scale/100)+"px";
 $("zoomVal").textContent=state.scale+"%";
 $("pcbPhoto").src=state.side==="front"?"front.webp":"back.webp";
 $("pcbPhoto").alt=state.side==="front"?"Taito Rainbow Islands PCB component side":"Taito Rainbow Islands PCB solder side";
 board.querySelectorAll(".hotspot").forEach(el=>el.remove());
 if(state.side==="back")return;
 const visible=DATA.nodes.filter(n=>(state.cat==="all"||n.category===state.cat)&&
 [n.id,n.name,n.role,n.category,n.address,n.priority,...n.rtl,tr("nodes",n.id,"name","")].join(" ").toLocaleLowerCase().includes(state.search.toLocaleLowerCase()));
 visible.forEach(n=>{
  if(!Array.isArray(n.rect))return;
  const [x,y,w,h]=n.rect,b=document.createElement("button");
  b.className="hotspot"+(state.selected.type==="node"&&state.selected.id===n.id?" selected":"");
  b.dataset.evidence=n.evidence;b.dataset.kind="node";b.dataset.id=n.id;
  b.style.left=(x/716*100)+"%";b.style.top=(y/711*100)+"%";
  b.style.width=(w/716*100)+"%";b.style.height=(h/711*100)+"%";
  b.title=tr("nodes",n.id,"name",n.name);
  b.setAttribute("aria-label",b.title);
  b.addEventListener("click",menu);board.appendChild(b);
 });
}
function renderDetail(){
 const {type,id}=state.selected;
 const isCircuit=type==="circuit";
 const n=(isCircuit?DATA.circuits:DATA.nodes).find(x=>x.id===id);
 if(!n)return;
 $("detailTitle").textContent=tr(isCircuit?"circuits":"nodes",id,isCircuit?"title":"name",isCircuit?n.title:n.name);
 const confidence=n.evidence==="region-estimated"?t("approx"):n.evidence==="label"?t("romLabel"):t("confirmed");
 $("detailSub").textContent=isCircuit?(t("statuses")[n.status]||n.status):((t("types")[n.category]||n.category)+" · "+confidence);
 let html="<h3>"+escape(t("about"))+"</h3><p>"+escape(tr(isCircuit?"circuits":"nodes",id,isCircuit?"summary":"role",isCircuit?n.summary:n.role))+"</p>";
 if(isCircuit){
   html+="<h3>"+escape(t("hardware"))+"</h3><div class='tags'>"+n.chips.map(tags).join(" ")+"</div>";
   if(n.pins?.length)html+="<h3>IC / PIN</h3><ul>"+n.pins.map(s=>"<li>"+escape(s)+"</li>").join("")+"</ul>";
   html+="<h3>"+escape(t("check"))+"</h3><ul>"+
     (tr("circuits",id,"checks",n.checks)||[]).map(s=>"<li>"+escape(s)+"</li>").join("")+"</ul>";
   html+="<div class='note'>"+escape(tr("circuits",id,"caution",n.confidence))+"</div>";
   html+="<p>"+link(n.source,t("read"))+"</p>";
   html+="<h3>"+escape(t("source"))+"</h3>"+sourceCards(n.rtl);
 }else{
   html+="<h3>"+escape(t("addr"))+"</h3><p><code>"+escape(n.address||"—")+"</code></p>";
   html+="<h3>"+escape(t("focus"))+"</h3><p>"+escape(tr("nodes",id,"priority",n.priority))+"</p>";
   if(n.evidence==="region-estimated")html+="<div class='note'>"+escape(t("approx"))+"</div>";
   const related=DATA.circuits.filter(c=>c.rtl.some(f=>n.rtl.includes(f))||c.chips.some(ch=>n.name.toLowerCase().includes(ch.toLowerCase()))).slice(0,5);
   if(related.length)html+="<h3>"+escape(t("related"))+"</h3><div class='chipList'>"+related.map(c=>'<button data-kind="circuit" data-id="'+escape(c.id)+'">'+escape(tr("circuits",c.id,"title",c.title))+"</button>").join("")+"</div>";
   html+="<h3>"+escape(t("source"))+"</h3>"+sourceCards(n.rtl);
 }
 $("detail").innerHTML=html;
 $("detail").querySelectorAll("button[data-kind]").forEach(b=>b.addEventListener("click",menu));
}
function renderRefs(){
 $("references").innerHTML=DATA.references.map(r=>"<div class='source'>"+link(r.url,r.title)+"</div>").join("")+
 "<div class='source'>"+link("https://commons.wikimedia.org/wiki/File:Rainbow_Islands_PCB.jpg",t("commonsSource"))+" · Noggin73 (2008, public domain)</div>"+
 "<p class='note'>"+escape(t("noFull"))+"</p>";
}
$("closeDetail").addEventListener("click",()=>closeSheet());
$("sheetBackdrop").addEventListener("click",()=>closeSheet());
document.addEventListener("keydown",e=>{if(e.key==="Escape"&&document.body.classList.contains("sheet-open")){e.preventDefault();closeSheet();}});
mobileSheet.addEventListener("change",()=>{if(!mobileSheet.matches)closeSheet(false);});
$("language").addEventListener("change",e=>{
 lang=e.target.value;
 try{localStorage.setItem("ri_pcb_language",lang)}catch{}
 setLanguage();renderRefs();
});
$("frontBtn").addEventListener("click",()=>{
 state.side="front";$("frontBtn").classList.add("active");$("backBtn").classList.remove("active");$("compareBtn").classList.remove("active");renderMap();
});
$("backBtn").addEventListener("click",()=>{
 state.side="back";$("backBtn").classList.add("active");$("frontBtn").classList.remove("active");$("compareBtn").classList.remove("active");renderMap();
});
$("compareBtn").addEventListener("click",()=>{
 state.side="compare";$("compareBtn").classList.add("active");$("frontBtn").classList.remove("active");$("backBtn").classList.remove("active");renderMap();
});
$("zoom").value=String(state.scale);
$("zoom").addEventListener("input",e=>{state.scale=+e.target.value;renderMap()});
$("search").addEventListener("input",e=>{state.search=e.target.value;renderLists();renderMap()});
$("category").addEventListener("change",e=>{state.cat=e.target.value;renderLists();renderMap()});
setLanguage();renderRefs();
})();