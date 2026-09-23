import cardMasonry from "../modifiers/card-masonry";
import ForumUser from "./food-user";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { modifier } from "ember-modifier";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import DRelativeDate from "./campus-relative-date";
import AppForm from "./food-form";
import Shop from "./food-shop";
import Entry from "./food-entry";
const modePresentation = {
  recommend: { icon: "utensils", label: "校友推荐" }, hot: { icon: "star", label: "人气热榜" },
  photos: { icon: "image", label: "实拍好店" }, dishes: { icon: "bowl-food", label: "必点菜品" },
  cheap: { icon: "coins", label: "平价好味" }, updated: { icon: "clock", label: "最近更新" },
};
const link = q => "/food?" + new URLSearchParams(q).toString();
const field = (name,label,type="text",required=true,extra={}) => ({name,label,type,required,...extra});
const statusText = s => ({pending:"待审核",approved:"已采纳",rejected:"未采纳",visible:"可见",hidden:"已隐藏",deleted:"已删除"}[s]||s);
const display = v => Array.isArray(v) ? v.join(", ") : v ?? "—";
const fieldName = v => ({name:"店名",area:"区域",category:"分类",body:"介绍",street:"地址",price_min:"最低人均",price_max:"最高人均",latitude:"纬度",longitude:"经度",business_status:"营业状态",status_reason:"状态说明",media_ids:"图片编号"}[v]||v);
export default class extends Component {
  @tracked snapshot;
  @tracked busy=false;
  @tracked error="";
  @tracked notice="";
  @tracked dialogForm=null;
  @tracked photoUrl=null;
  @tracked localFavorites=[];
  dirty=false;
  version=0;
  constructor(){
    super(...arguments);
    try { const ids=JSON.parse(localStorage.getItem("riverside:food:favorites")||"[]");this.localFavorites=Array.isArray(ids)?ids.filter(Number.isInteger):[]; } catch { this.localFavorites=[]; }
    // Hydrate a direct guest bookmark once. Reading snapshot inside a modifier
    // made each response rerun the modifier and request the same list again.
    if(this.data.view==="favorites" && !this.data.member) {
      const query={...this.data.q,view:"favorites",ids:this.localFavorites.join(",")};
      queueMicrotask(()=>{if(!this.isDestroying&&!this.isDestroyed)this.navigate(query,null,true);});
    }
  }
  mount=modifier(()=>{
    const pop=()=>this.navigate(Object.fromEntries(new URLSearchParams(location.search)),null,true);
    const leave=e=>{if(this.dirty){e.preventDefault();e.returnValue="";}};
    const key=e=>{if(e.key==="Escape") { this.photoUrl=null; }};
    addEventListener("popstate",pop);addEventListener("beforeunload",leave);addEventListener("keydown",key);
    return ()=>{removeEventListener("popstate",pop);removeEventListener("beforeunload",leave);removeEventListener("keydown",key);};
  });
  get data(){return this.snapshot||this.args.model;}
  get query(){return Object.fromEntries(new URLSearchParams(location.search));}
  get shops(){return (this.data.shops||[]).map(s=>({...s,favorite:this.data.member?s.favorite:this.localFavorites.includes(s.id)}));}
  get shop(){const s=this.data.shop;return s?{...s,favorite:this.data.member?s.favorite:this.localFavorites.includes(s.id)}:null;}
  get modes(){return (this.data.modes||[]).map(m=>({...m,...modePresentation[m.id]}));}
  get filtered(){return ["q","category","price","min_rating","status","sort"].some(k=>!!this.data.q?.[k]) || (!!this.data.q?.area && this.data.q.area!=="全部");}
  get resultTitle(){return this.data.view==="favorites"?"我的收藏":this.data.view==="discover"?(modePresentation[this.data.q.mode||"recommend"]?.label||"校友推荐"):"发现好店";}
  @action applyFilters(e){e.target.form.requestSubmit();}
  @action resetFilters(){return this.navigate({view:this.data.view,mode:this.data.q.mode||""});}
  get isCatalog(){return ["discover","shops","favorites"].includes(this.data.view);}
  get showComments(){return this.data.view==="about"||this.data.part==="reviews"||(this.data.view==="admin"&&this.data.part==="comments");}
  get paging(){return this.isCatalog||this.showComments||["admin","contribute"].includes(this.data.view);}
  get parts(){return (this.data.view==="admin"?[["proposals","投稿审核"],["shops","门店"],["comments","点评"],["reports","举报"],["audits","操作记录"],["about","关于页面"]]:[["overview","概览"],["dishes","推荐菜"],["reviews","校友点评"],["photos","实拍相册"],["history","共建记录"]]).map(([id,label])=>({id,label}));}
  @action dirtyChanged(){this.dirty=true;}
  @action async visit(e){if(e.metaKey||e.ctrlKey||e.shiftKey||e.altKey||e.button>0)return;e.preventDefault();return this.navigate(Object.fromEntries(new URL(e.currentTarget.href).searchParams));}
  @action async navigate(q,event,fromHistory=false){
    event?.preventDefault();if(this.dirty&&!confirm("尚未提交的内容会丢失，确定离开吗？"))return;
    if(q.view==="favorites"&&!this.data.member)q={...q,ids:this.localFavorites.join(",")};
    const version=++this.version;this.busy=true;this.error="";this.dialogForm=null;this.dirty=false;
    const search=new URLSearchParams(q).toString();
    try{const result=await ajax("/food/state.json?"+search);if(version!==this.version)return;this.snapshot=result;if(!fromHistory&&location.search!=="?"+search)history.pushState({},"",link(q));requestAnimationFrame(()=>{if(q.reply)document.getElementById(`food-reply-${q.reply}`)?.scrollIntoView({block:"center"});else scrollTo({top:0,behavior:"instant"});});}
    catch(e){this.error=extractError(e);}finally{if(version===this.version)this.busy=false;}
  }
  @action tab(view){this.notice="";return this.navigate({view});}
  @action setQuery(key,value){const q={...this.query,[key]:value};delete q.page;return this.navigate(q);}
  @action select(key,e){return this.setQuery(key,e.target.value);}
  @action page(page){return this.navigate({...this.query,page,seed:this.data.seed||this.query.seed||""});}
  @action search(e){e.preventDefault();return this.navigate({...Object.fromEntries(new FormData(e.target)),view:this.data.view==="discover"?"shops":this.data.view,seed:this.data.seed||""});}
  @action shuffle(){return this.setQuery("seed",Math.floor(Date.now()/1000));}
  @action async execute(operation,data,requestId){
    const result=await ajax("/food/action",{type:"POST",contentType:"application/json",data:JSON.stringify({operation,data,request_id:requestId})});
    this.dirty=false;this.dialogForm=null;
    if(result.query)await this.navigate(result.query);else this.snapshot=await ajax("/food/state.json?"+new URLSearchParams(this.query));
    this.notice=result.message||"已保存";return result;
  }
  @action async mutate(op,data){if(this.busy)return;this.busy=true;this.error="";try{await this.execute(op,data,crypto.randomUUID());}catch(e){this.error=extractError(e);}finally{this.busy=false;}}
  @action async favorite(shop){
    if(this.data.member){if(this.data.readonly){this.notice="只读预览期间不能修改账号收藏";return;}return this.mutate("favorite",{id:shop.id});}
    const ids=this.localFavorites.includes(shop.id)?this.localFavorites.filter(id=>id!==shop.id):[...this.localFavorites,shop.id];
    try{localStorage.setItem("riverside:food:favorites",JSON.stringify(ids));this.localFavorites=ids;this.notice="收藏已保存在此浏览器";if(this.data.view==="favorites")await this.navigate({...this.query,ids:ids.join(",")},null,true);}catch{this.error="浏览器无法保存收藏，请允许本站使用本地存储";}
  }
  @action react(item){return this.mutate("react",{kind:item.kind,id:item.id,value:item.liked?0:1});}
  @action reply(item){this.dialogForm={title:`回复 ${item.author.name}`,operation:"comment",fields:[field("body","回复内容","textarea",true,{maxlength:1200})],data:{kind:item.target_kind,id:item.target_id,parent_id:item.id},button:"发布回复"};}
  @action report(item){this.dialogForm={title:"举报内容",operation:"report",fields:[field("reason","举报原因","textarea",true,{maxlength:500})],data:{kind:item.kind,id:item.id},button:"提交举报"};}
  @action remove(item){if(confirm("确定删除这条内容吗？"))return this.mutate("delete_own",{kind:item.kind,id:item.id});}
  @action moderate(item){this.dialogForm={title:"管理内容",operation:"moderate",fields:[field("status","可见状态","select",true,{value:item.status||"visible",options:[{value:"visible",label:"可见"},{value:"hidden",label:"隐藏"},{value:"deleted",label:"删除"}]}),field("reason","处理原因","textarea",true,{maxlength:500})],data:{kind:item.kind||"Shop",id:item.id},button:"保存处理"};}
  @action review(p,decision){this.dialogForm={title:decision==="approve"?"采纳这次贡献":"不采纳这次贡献",operation:"review_proposal",fields:[field("reason","审核说明","textarea",true,{maxlength:500}),...(p.stale&&decision==="approve"?[field("accept_conflicts","已核对修改前、申请修改与当前资料，确认采纳申请中变动的字段","checkbox",true)]:[])],data:{id:p.id,decision,review_version:p.review_version},button:"确认审核"};}
  @action closeDialog(){if(!this.dirty||confirm("放弃尚未提交的内容？")){this.dialogForm=null;this.dirty=false;}}
  @action photo(url){this.photoUrl=url;}
  @action closePhoto(){this.photoUrl=null;}
  @action resolve(report){return this.mutate("resolve_report",{id:report.id});}
  @action async share(){try{await navigator.clipboard.writeText(location.origin+link({view:"shop",id:this.shop.id}));this.notice="门店链接已复制";}catch{this.notice="请复制浏览器地址栏中的链接";}}
  @action poster(){
    const s=this.shop,c=document.createElement("canvas");c.width=1000;c.height=700;const x=c.getContext("2d");x.fillStyle="#fbf7ed";x.fillRect(0,0,1000,700);x.fillStyle="#925b30";x.font="26px sans-serif";x.fillText("RIVERSIDE / 觅电",60,85);x.fillStyle="#292725";x.font="bold 48px sans-serif";x.fillText(s.name.slice(0,18),60,180);x.font="28px sans-serif";x.fillText(`${s.area} · ${s.price} · ${s.rating||"暂无"} 分`,60,250);x.font="25px sans-serif";let line="",y=330;for(const ch of (s.body||s.review||"校友一起发现的好味道")){if(x.measureText(line+ch).width>860){x.fillText(line,60,y);y+=40;line="";if(y>500)break;}line+=ch;}if(y<=500)x.fillText(line,60,y);x.font="19px sans-serif";x.fillText(location.origin+link({view:"shop",id:s.id}),60,610);const a=document.createElement("a");a.href=c.toDataURL("image/png");a.download="觅电分享.png";a.click();
  }
  <template>
    <main class="food-native" data-view={{this.data.view}} aria-busy={{if this.busy "true" "false"}} {{this.mount}}>
      <h1 class="sr-only">觅电</h1>
      <nav class="food-nav" aria-label="觅电导航"><div class="food-tab-links">{{#each this.data.tabs as |tab|}}<a href={{link (hash view=tab.id)}} class={{if (eq this.data.view tab.id) "active"}} aria-current={{if (eq this.data.view tab.id) "page"}} {{on "click" this.visit}}>{{tab.label}}</a>{{/each}}</div>{{#if this.data.member}}<a class="btn btn-primary food-create" href="/food?view=contribute" {{on "click" this.visit}}>{{dIcon "plus"}} 推荐新店</a>{{/if}}</nav>
      {{#if this.data.readonly}}<p class="food-banner">当前为只读预览，可以浏览店铺和历史内容。</p>{{/if}}
      {{#if this.error}}<p class="alert alert-error" role="alert">{{this.error}}</p>{{/if}}{{#if this.notice}}<p class="alert alert-success" role="status">{{this.notice}}</p>{{/if}}
      {{#if this.isCatalog}}
        <section class="food-discovery" aria-label="查找美食">
          <form class="food-search" role="search" {{on "submit" this.search}}>
            <div class="food-search-box">{{dIcon "magnifying-glass"}}<input type="search" name="q" value={{this.data.q.q}} placeholder="搜店名、地址或想吃的菜" aria-label="搜索店铺" /><button type="submit" class="btn btn-primary" disabled={{this.busy}}>搜索</button></div>
            {{#if (eq this.data.view "discover")}}<div class="food-modes" aria-label="发现方式">{{#each this.modes key="id" as |mode|}}<button type="button" class="food-mode {{if (eq (if this.data.q.mode this.data.q.mode 'recommend') mode.id) 'is-selected'}}" aria-pressed={{if (eq (if this.data.q.mode this.data.q.mode 'recommend') mode.id) "true" "false"}} disabled={{this.busy}} {{on "click" (fn this.setQuery "mode" mode.id)}}><span class="food-mode-icon">{{dIcon mode.icon}}</span><span>{{mode.label}}</span></button>{{/each}}</div>{{/if}}
            <div class="food-area-row"><span class="food-filter-label">{{dIcon "location-dot"}} 区域</span><div class="food-areas">{{#each this.data.areas as |area|}}<button type="button" class="btn btn-flat {{if (eq (if this.data.q.area this.data.q.area '全部') area.name) 'is-selected'}}" aria-pressed={{if (eq (if this.data.q.area this.data.q.area '全部') area.name) "true" "false"}} disabled={{this.busy}} {{on "click" (fn this.setQuery "area" area.name)}}>{{area.name}} <small>{{area.count}}</small></button>{{/each}}</div></div>
            <div class="food-filter-row"><select name="category" aria-label="分类" disabled={{this.busy}} {{on "change" this.applyFilters}}><option value="">全部分类</option>{{#each this.data.categories as |category|}}<option value={{category}} selected={{eq category this.data.q.category}}>{{category}}</option>{{/each}}</select><select name="price" aria-label="人均价格" disabled={{this.busy}} {{on "change" this.applyFilters}}><option value="">全部价格</option><option value="1" selected={{eq this.data.q.price "1"}}>10 元以下</option><option value="2" selected={{eq this.data.q.price "2"}}>10–20 元</option><option value="3" selected={{eq this.data.q.price "3"}}>20–30 元</option><option value="4" selected={{eq this.data.q.price "4"}}>30–50 元</option><option value="5" selected={{eq this.data.q.price "5"}}>50 元以上</option></select><select name="sort" aria-label="排序" disabled={{this.busy}} {{on "change" this.applyFilters}}><option value="">默认排序</option><option value="rating-desc" selected={{eq this.data.q.sort "rating-desc"}}>评分优先</option><option value="price-asc" selected={{eq this.data.q.sort "price-asc"}}>价格从低到高</option><option value="price-desc" selected={{eq this.data.q.sort "price-desc"}}>价格从高到低</option><option value="newest" selected={{eq this.data.q.sort "newest"}}>最新收录</option></select><select name="min_rating" aria-label="最低评分" disabled={{this.busy}} {{on "change" this.applyFilters}}><option value="">全部评分</option><option value="4" selected={{eq this.data.q.min_rating "4"}}>4 星以上</option><option value="3" selected={{eq this.data.q.min_rating "3"}}>3 星以上</option><option value="2" selected={{eq this.data.q.min_rating "2"}}>2 星以上</option></select><select name="status" aria-label="营业状态" disabled={{this.busy}} {{on "change" this.applyFilters}}><option value="">全部状态</option><option value="open" selected={{eq this.data.q.status "open"}}>营业中</option><option value="closed" selected={{eq this.data.q.status "closed"}}>暂停营业</option></select>{{#if this.filtered}}<button type="button" class="btn btn-flat food-reset" disabled={{this.busy}} {{on "click" this.resetFilters}}>重置</button>{{/if}}</div>
            <input type="hidden" name="area" value={{this.data.q.area}} /><input type="hidden" name="mode" value={{this.data.q.mode}} />
          </form>
        </section>
        <div class="food-results-heading"><div><h2>{{this.resultTitle}}</h2><span>{{this.data.pagination.total}} 家店铺{{#if (eq this.data.view "discover")}} · 校友一起发现的好味道{{/if}}</span></div>{{#if (eq this.data.view "discover")}}<button type="button" class="btn btn-flat" disabled={{this.busy}} {{on "click" this.shuffle}}>{{dIcon "rotate"}} 换一批</button>{{/if}}</div>
        {{#if (eq this.data.view "favorites")}}<p class="food-muted">{{#if this.data.member}}收藏已与论坛账号同步。{{else}}收藏保存在当前浏览器；登录论坛后可以使用账号收藏。{{/if}}</p>{{/if}}
        <div class="food-grid" {{cardMasonry ".food-shop"}}>{{#each this.shops key="id" as |shop|}}<Shop @shop={{shop}} @visit={{this.visit}} @favorite={{this.favorite}} />{{else}}<div class="food-empty">{{dIcon "utensils"}}<h3>这里还没有店铺</h3><p>试试其他筛选，或推荐一家你喜欢的店。</p></div>{{/each}}</div>
      {{/if}}
      {{#if this.shop}}
        <a class="food-back" href="/food?view=shops" {{on "click" this.visit}}>← 全部店铺</a>
        <section class="food-detail-head">{{#if this.shop.cover}}<button type="button" class="food-detail-cover" aria-label="放大门店封面" {{on "click" (fn this.photo this.shop.cover)}}><img src={{this.shop.cover}} alt={{this.shop.name}} /></button>{{else}}<div class="food-detail-cover food-no-photo">{{dIcon "utensils"}}<small>等你来晒美食</small></div>{{/if}}<div class="food-detail-main"><div class="food-eyebrow">{{this.shop.area}} · {{this.shop.category}}</div><h2>{{this.shop.name}}</h2><div class="food-detail-meta"><span class="food-rating">{{dIcon "star"}} {{if this.shop.rating this.shop.rating "暂无评分"}}</span><span class="food-detail-price">{{this.shop.price}}{{#unless (eq this.shop.price "价格未知")}} / 人均{{/unless}}</span><span>{{this.shop.comments_count}} 条点评</span><span>{{this.shop.dishes_count}} 道推荐菜</span></div><p>{{dIcon "location-dot"}} {{if this.shop.street this.shop.street "地址待完善"}}</p>{{#if (eq this.shop.business_status "closed")}}<p class="food-banner">暂停营业 · {{this.shop.status_reason}}</p>{{/if}}</div><div class="food-actions"><button class="btn {{if this.shop.favorite 'is-active'}}" {{on "click" (fn this.favorite this.shop)}}>{{dIcon "heart"}} {{if this.shop.favorite "已收藏" "收藏"}}</button><button class="btn" {{on "click" this.share}}>{{dIcon "link"}} 分享</button><button class="btn" {{on "click" this.poster}}>{{dIcon "download"}} 分享卡片</button>{{#if this.data.can_write}}<a class="btn" href={{link (hash view="edit" id=this.shop.id)}} {{on "click" this.visit}}>{{dIcon "pen-to-square"}} 完善资料</a>{{/if}}{{#if this.data.can_manage}}<button class="btn" {{on "click" (fn this.moderate this.shop)}}>管理门店</button>{{/if}}</div></section>
      {{/if}}
      {{#if this.data.part}}<nav class="food-subnav" aria-label="内容分栏">{{#each this.parts as |part|}}<button class="btn btn-flat {{if (eq part.id this.data.part) 'is-selected'}}" {{on "click" (fn this.setQuery "part" part.id)}}>{{part.label}}</button>{{/each}}</nav>{{/if}}
      {{#if this.shop}}
        {{#if (eq this.data.part "overview")}}<section class="food-overview"><div><h3>关于这家店</h3><p class="food-body">{{if this.shop.body this.shop.body "介绍还待校友补充。"}}</p>{{#if this.shop.review}}<blockquote class="food-body">{{this.shop.review}}</blockquote>{{/if}}<div class="food-tags">{{#each this.shop.review_tags as |tag|}}<span>{{tag.tag}} {{tag.count}}</span>{{/each}}</div>{{#if this.shop.source_url}}<a href={{this.shop.source_url}} target="_blank" rel="noopener noreferrer">查看原始来源 ↗</a>{{/if}}{{#if this.shop.latitude}}<p class="food-muted">位置：{{this.shop.latitude}}, {{this.shop.longitude}}</p>{{/if}}{{#if this.shop.missing_media_count}}<p class="food-muted">{{this.shop.missing_media_count}} 张历史图片已缺失</p>{{/if}}</div><div class="food-photos">{{#each this.shop.images as |url|}}<button {{on "click" (fn this.photo url)}} aria-label="放大门店照片"><img src={{url}} alt="门店照片" loading="lazy" /></button>{{/each}}</div></section><h3>同一区域，再逛逛</h3><div class="food-grid food-related" {{cardMasonry ".food-shop"}}>{{#each this.data.related key="id" as |shop|}}<Shop @shop={{shop}} @visit={{this.visit}} @favorite={{this.favorite}} />{{/each}}</div>{{/if}}
        {{#if (eq this.data.part "photos")}}{{#each this.data.gallery as |group|}}<h3>{{group.label}}</h3><div class="food-photos is-gallery">{{#each group.images as |url|}}<button {{on "click" (fn this.photo url)}} aria-label="放大图片"><img src={{url}} alt={{group.label}} loading="lazy" /></button>{{else}}<p class="food-muted">还没有这类照片。</p>{{/each}}</div>{{/each}}{{/if}}
        {{#if (eq this.data.part "history")}}<div class="food-history">{{#each this.data.history as |item|}}<p><ForumUser @user={{item.author}} @name={{item.author.name}} /> {{item.body}} <DRelativeDate @date={{item.created_at}} /></p>{{else}}<p class="food-empty">暂无共建记录。</p>{{/each}}</div>{{/if}}
        {{#if (eq this.data.part "dishes")}}<div class="food-toolbar"><h3>校友推荐菜</h3><select aria-label="菜品排序" {{on "change" (fn this.select "dishes_sort")}}><option value="likes" selected={{eq this.data.q.dishes_sort "likes"}}>最多赞</option><option value="newest" selected={{eq this.data.q.dishes_sort "newest"}}>最新发布</option></select></div>{{#each this.data.dishes as |entry|}}<Entry @busy={{this.busy}} @entry={{entry}} @visit={{this.visit}} @photo={{this.photo}} @react={{this.react}} @report={{this.report}} @remove={{this.remove}} @moderate={{this.moderate}} />{{else}}<p class="food-empty">还没有推荐菜，来分享你的必点吧。</p>{{/each}}{{#if this.data.dish_form}}<AppForm @form={{this.data.dish_form}} @execute={{this.execute}} @dirty={{this.dirtyChanged}} />{{/if}}{{/if}}
      {{/if}}
      {{#if (eq this.data.view "about")}}
        <section class="cooked food-about">{{{this.data.about_html}}}{{#if this.data.about_updated_at}}<p class="food-muted">最后更新于 <DRelativeDate @date={{this.data.about_updated_at}} /></p>{{/if}}{{#if this.data.admin}}<a class="btn" href="/food?view=admin&part=about" {{on "click" this.visit}}>编辑关于页面</a>{{/if}}</section>
        {{#if this.data.contributors.length}}<section class="food-contributors" aria-label="贡献榜"><h2>贡献榜 <small>{{this.data.contributors.length}} 位贡献者</small></h2><ol>{{#each this.data.contributors key="id" as |contributor|}}<li><span class="food-contributor-rank">{{contributor.rank}}</span><div><ForumUser @user={{contributor.author}} @name={{contributor.author.name}} /><p>贡献 {{contributor.shop_count}} 家店铺</p></div>{{#if (eq contributor.rank 1)}}<span class="food-contributor-first">TOP 1</span>{{/if}}</li>{{/each}}</ol></section>{{/if}}
      {{/if}}
      {{#if this.showComments}}<div class="food-toolbar"><h3>校友点评与讨论</h3><div><select aria-label="点评排序" {{on "change" (fn this.select "comments_sort")}}><option value="newest" selected={{eq this.data.q.comments_sort "newest"}}>最新发布</option><option value="oldest" selected={{eq this.data.q.comments_sort "oldest"}}>最早发布</option><option value="likes" selected={{eq this.data.q.comments_sort "likes"}}>最多赞</option></select><select aria-label="点评筛选" {{on "change" (fn this.select "comments_filter")}}><option value="">全部点评</option><option value="photos" selected={{eq this.data.q.comments_filter "photos"}}>有图</option><option value="good" selected={{eq this.data.q.comments_filter "good"}}>好评</option><option value="cheap" selected={{eq this.data.q.comments_filter "cheap"}}>便宜</option><option value="warning" selected={{eq this.data.q.comments_filter "warning"}}>避雷</option><option value="liked" selected={{eq this.data.q.comments_filter "liked"}}>有赞</option></select></div></div>{{#each this.data.comments key="id" as |entry|}}<Entry @busy={{this.busy}} @entry={{entry}} @visit={{this.visit}} @photo={{this.photo}} @react={{this.react}} @reply={{this.reply}} @report={{this.report}} @remove={{this.remove}} @moderate={{this.moderate}} />{{else}}<p class="food-empty">暂无符合条件的点评。</p>{{/each}}{{#if this.data.comment_form}}<AppForm @form={{this.data.comment_form}} @execute={{this.execute}} @dirty={{this.dirtyChanged}} />{{/if}}{{/if}}
      {{#if (eq this.data.view "admin")}}
        {{#if (eq this.data.part "proposals")}}<select aria-label="申请类型" {{on "change" (fn this.select "proposal_kind")}}><option value="all">全部申请</option><option value="new" selected={{eq this.data.q.proposal_kind "new"}}>新店投稿</option><option value="edit" selected={{eq this.data.q.proposal_kind "edit"}}>资料修改</option></select><select aria-label="申请状态" {{on "change" (fn this.select "status")}}><option value="pending">待审核</option><option value="approved" selected={{eq this.data.q.status "approved"}}>已采纳</option><option value="rejected" selected={{eq this.data.q.status "rejected"}}>未采纳</option><option value="all" selected={{eq this.data.q.status "all"}}>全部</option></select>{{/if}}
        {{#each this.shops as |shop|}}<div class="food-admin-row"><a href={{shop.url}} {{on "click" this.visit}}>{{shop.name}}</a><span>{{shop.area}} · {{statusText shop.status}}</span>{{#unless this.data.readonly}}<button class="btn" {{on "click" (fn this.moderate shop)}}>管理</button>{{/unless}}</div>{{/each}}
        {{#each this.data.reports as |report|}}<div class="food-admin-row"><a href={{report.url}} {{on "click" this.visit}}>查看被举报内容</a><span>{{report.reason}}</span>{{#unless this.data.readonly}}<button class="btn" {{on "click" (fn this.resolve report)}}>标记处理完成</button>{{/unless}}</div>{{/each}}
        {{#each this.data.audits as |audit|}}<div class="food-admin-row"><strong><ForumUser @user={{audit.actor}} @name={{audit.actor.name}} /></strong><span>{{audit.action}} · {{audit.reason}}</span><DRelativeDate @date={{audit.created_at}} /></div>{{/each}}
      {{/if}}
      {{#each this.data.forms as |form|}}<AppForm @form={{form}} @execute={{this.execute}} @dirty={{this.dirtyChanged}} />{{/each}}
      {{#each this.data.proposals as |proposal|}}<article class="food-proposal"><header><h3>{{proposal.title}}</h3><span>{{statusText proposal.status}}</span></header><p><ForumUser @user={{proposal.author}} @name={{proposal.author.name}} /> · {{proposal.reason}} <DRelativeDate @date={{proposal.created_at}} /></p>{{#if proposal.review_reason}}<p>审核说明：{{proposal.review_reason}}</p>{{/if}}{{#if proposal.stale}}<p class="food-banner">这份申请基于旧资料，请逐项核对当前内容。</p>{{/if}}<details><summary>查看修改对照</summary><div class="food-table-wrap"><table><thead><tr><th>字段</th><th>修改前</th><th>申请修改</th><th>当前资料</th></tr></thead><tbody>{{#each proposal.diffs as |diff|}}<tr class={{if diff.conflict "food-conflict"}}><th>{{fieldName diff.field}}{{#if diff.conflict}} · 有冲突{{/if}}</th><td>{{display diff.before}}</td><td>{{display diff.after}}</td><td>{{display diff.current}}</td></tr>{{/each}}</tbody></table></div></details><div class="food-photos">{{#each proposal.images as |url|}}<button {{on "click" (fn this.photo url)}} aria-label="放大申请图片"><img src={{url}} alt="申请图片" /></button>{{/each}}</div>{{#if proposal.missing_media_count}}<p class="food-muted">{{proposal.missing_media_count}} 张历史图片缺失</p>{{/if}}{{#if (eq this.data.view "admin")}}{{#unless this.data.readonly}}{{#if (eq proposal.status "pending")}}<div class="food-actions"><button class="btn btn-primary" {{on "click" (fn this.review proposal "approve")}}>采纳</button><button class="btn" {{on "click" (fn this.review proposal "reject")}}>不采纳</button></div>{{/if}}{{/unless}}{{/if}}</article>{{/each}}
      {{#if this.paging}}{{#if this.data.pagination}}<nav class="food-pagination" aria-label="分页"><button class="btn" disabled={{unless this.data.pagination.previous true}} {{on "click" (fn this.page this.data.pagination.previous)}}>上一页</button><span>第 {{this.data.pagination.page}} / {{this.data.pagination.pages}} 页 · {{this.data.pagination.total}} 项</span><button class="btn" disabled={{unless this.data.pagination.next true}} {{on "click" (fn this.page this.data.pagination.next)}}>下一页</button></nav>{{/if}}{{/if}}
      {{#unless this.data.member}}<p class="food-banner">登录论坛并完成校友认证后，即可分享点评、推荐菜品和完善店铺。</p>{{/unless}}
      {{#if this.dialogForm}}<div class="food-overlay"><section class="food-dialog" role="dialog" aria-modal="true" aria-label={{this.dialogForm.title}}><button class="btn food-dialog-close" {{on "click" this.closeDialog}}>关闭</button><AppForm @form={{this.dialogForm}} @execute={{this.execute}} @dirty={{this.dirtyChanged}} /></section></div>{{/if}}
      {{#if this.photoUrl}}<div class="food-overlay" role="dialog" aria-modal="true" aria-label="查看图片"><button class="btn food-photo-close" {{on "click" this.closePhoto}}>关闭图片</button><img class="food-lightbox" src={{this.photoUrl}} alt="放大的美食照片" /></div>{{/if}}
    </main>
  </template>
}
