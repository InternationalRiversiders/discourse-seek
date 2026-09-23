# frozen_string_literal: true
require 'cgi'
module DiscourseSeek
  %w[Shop Dish Proposal Favorite AboutPage].each do |name|
    klass=Class.new(Record);klass.table_name="river_food_#{name.underscore.pluralize}";const_set(name,klass)
  end
  module Service
    AREAS=%w[南门 西门 犀浦 红光 食堂 其他].freeze
    CATEGORIES=%w[火锅 烧烤 快餐 面食 川菜 湘菜 粤菜 日料 韩料 西餐 甜品饮品 小吃 其他].freeze
    REVIEW_TAGS=%w[好吃 便宜 量大 一人食 聚餐 夜宵 外带 出餐快 排队久 服务好 环境好 踩雷].freeze
    DISH_TAGS={'must'=>'必点','normal'=>'一般','avoid'=>'避雷'}.freeze
    MODES=[['recommend','推荐'],['hot','热榜'],['photos','有图'],['dishes','菜品'],['cheap','便宜'],['updated','新维护']].freeze
    ADMIN_OPS=%w[save_shop review_proposal moderate resolve_report save_about link_identity].freeze
    def self.targets = {'Shop'=>Shop,'Dish'=>Dish,'Comment'=>Comment,'AboutPage'=>AboutPage}
    def self.authorize!(user,op)
      Access.check!(user,admin:ADMIN_OPS.include?(op))
    end
    def self.parse_review(body)
      match=body.to_s.match(/\n*<!--review-tags:([^>]*)-->\s*\z/)
      return [body.to_s,[]] unless match
      tags=match[1].split(',').map { |s| CGI.unescape(s) }.select { |s| REVIEW_TAGS.include?(s) }.uniq.first(6)
      [body.to_s.sub(/\n*<!--review-tags:([^>]*)-->\s*\z/,'').strip,tags]
    end
    def self.parse_dish(body)
      match=body.to_s.match(/\n*<!--dish-tag:(must|normal|avoid)-->\s*\z/)
      match ? [body.to_s.sub(/\n*<!--dish-tag:(must|normal|avoid)-->\s*\z/,'').strip,match[1]] : [body.to_s,nil]
    end
    def self.visible!(item,user,admin:false)
      raise Discourse::InvalidAccess unless item.status=='visible' || (admin && Access.admin?(user))
      if item.is_a?(Dish)
        visible!(Shop.find(item.shop_id),user,admin:admin)
      elsif item.is_a?(Comment)
        root=targets[item.target_kind]&.find_by(id:item.target_id)
        raise Discourse::InvalidAccess unless root && !root.is_a?(Comment)
        visible!(root,user,admin:admin)
      end
      item
    end
    def self.url(item)
      return "/food?view=shop&id=#{item.id}" if item.is_a?(Shop)
      return "/food?view=shop&id=#{item.shop_id}&part=dishes" if item.is_a?(Dish)
      return item.target_kind=='Shop' ? "/food?view=shop&id=#{item.target_id}&part=reviews&reply=#{item.id}" : "/food?view=about&reply=#{item.id}" if item.is_a?(Comment)
      '/food?view=about'
    end
    def self.pagination(rows,query,limit=20)
      total=rows.length;pages=[(total.to_f/limit).ceil,1].max;page=[[query['page'].to_i,1].max,pages].min
      [rows.slice((page-1)*limit,limit).to_a,{page:page,pages:pages,total:total,previous:page>1 ? page-1 : nil,next:page<pages ? page+1 : nil}]
    end
    def self.numeric(value,min:nil,max:nil)
      return nil if value.nil? || value.to_s.strip.empty?
      n=Float(value);raise Error,'数值超出范围' unless n.finite? && (!min || n>=min) && (!max || n<=max);n
    end
    def self.price_label(details)
      return "¥#{details['price_text']}" if details['price_text'].present?
      min=details['price_min'];max=details['price_max'];format=->(x) { x.to_f==x.to_i ? x.to_i.to_s : x.to_s }
      return "¥#{format.call(min)}–#{format.call(max)}" if min && max
      return "¥#{format.call(min)}+" if min
      max ? "¥#{format.call(max)}以内" : '价格未知'
    end
    def self.summary(shop,comments:[],dishes:[],proposals:[],favorites:[],likes:{})
      ratings=comments.select { |c| c.parent_id.nil? && c.rating }.map { |c| c.rating.to_f };ratings.unshift(shop.base_rating.to_f) if shop.base_rating
      latest_comment=comments.select { |c| c.parent_id.nil? && c.body.present? }.max_by(&:created_at)
      sorted_dishes=dishes.sort_by { |d| [-likes.fetch(d.id,0),-d.created_at.to_f,-d.id] }
      times=[shop.created_at,shop.updated_at,*dishes.map(&:created_at),*proposals.map { |p| p.reviewed_at || p.updated_at }].compact
      photos=shop.media_ids+comments.flat_map(&:media_ids)+sorted_dishes.first(3).flat_map(&:media_ids)
      {id:shop.id,name:shop.name,area:shop.area,category:shop.category,body:shop.body,review:shop.review,street:shop.details['street'],price:price_label(shop.details),price_min:shop.details['price_min'],price_max:shop.details['price_max'],rating:ratings.empty? ? nil : (ratings.sum/ratings.length).round(1),base_rating:shop.base_rating&.to_f,user_rating_count:comments.count { |c| c.parent_id.nil? && c.rating },comments_count:comments.length,dishes_count:dishes.length,photo_count:photos.length+shop.missing_media_count+comments.sum(&:missing_media_count)+sorted_dishes.first(3).sum(&:missing_media_count),images:Shared.media_urls(shop.media_ids),cover:Shared.media_urls(photos.first(1)).first,recommended_dishes:sorted_dishes.first(3).map(&:name),latest_comment:latest_comment&.body&.truncate(100),review_tags:tag_summary(comments),business_status:shop.business_status,status_reason:shop.status_reason,status:shop.status,created_at:shop.created_at,updated_at:shop.updated_at,activity_at:times.max,source_url:Shared.safe_url(shop.details['source_url']),latitude:shop.details['latitude'],longitude:shop.details['longitude'],author:Shared.author(shop.user_id),favorite:favorites.include?(shop.id),missing_media_count:shop.missing_media_count,url:url(shop)}
    end
    def self.tag_summary(comments)
      comments.select { |c| c.parent_id.nil? }.flat_map(&:tags).tally.sort_by { |tag,count| [-count,%w[便宜 踩雷 出餐快 服务好 好吃 环境好 聚餐 量大 排队久 外带 夜宵 一人食].index(tag) || 99] }.first(3).map { |tag,count| {tag:tag,count:count} }
    end
    def self.catalog(user,include_hidden:false)
      shops=(include_hidden ? Shop.all : Shop.where(status:'visible')).order(:id).to_a;ids=shops.map(&:id)
      comments=Comment.where(target_kind:'Shop',target_id:ids,status:'visible').order(:id).to_a.group_by(&:target_id)
      dishes=Dish.where(shop_id:ids,status:'visible').to_a.group_by(&:shop_id)
      proposals=Proposal.where(shop_id:ids,status:'approved').to_a.group_by(&:shop_id)
      favorites=user ? Favorite.where(user_id:user.id).pluck(:shop_id) : []
      likes=Reaction.where(target_kind:'Dish',value:1).group(:target_id).count
      shops.map { |s| summary(s,comments:comments[s.id] || [],dishes:dishes[s.id] || [],proposals:proposals[s.id] || [],favorites:favorites,likes:likes) }
    end
    def self.score(s,seed,now=Time.current)
      days=s[:activity_at] ? [(now-s[:activity_at])/86400,0].max : nil
      x=Math.sin(s[:id]*9301+seed*49297)*233280;noise=x-x.floor
      (s[:rating] || 3.3)*12+s[:comments_count]*1.4+s[:dishes_count]*2.4+s[:photo_count]*0.45+(days ? [0,10-days/7].max : 0)+noise*10
    end
    def self.discover(rows,mode,seed)
      now=Time.current
      case mode
      when 'hot' then rows.sort_by { |s| [-(s[:rating] || 0),-s[:comments_count],s[:id]] }
      when 'photos' then rows.select { |s| s[:photo_count]>0 }.sort_by { |s| [-s[:photo_count],-score(s,seed,now)] }
      when 'dishes' then rows.select { |s| s[:dishes_count]>0 }.sort_by { |s| [-s[:dishes_count],-score(s,seed,now)] }
      when 'cheap' then rows.select { |s| (s[:price_min] || s[:price_max] || 0)<=20 }.sort_by { |s| [s[:price_min] || s[:price_max] || 999,-score(s,seed,now)] }
      when 'updated' then rows.sort_by { |s| [-(s[:activity_at]&.to_f || 0),s[:id]] }
      else rows.sort_by { |s| [-score(s,seed,now),s[:id]] }
      end
    end
    def self.filter(rows,q)
      rows=rows.select { |s| s[:area]==q['area'] } if q['area'].present? && q['area']!='全部'
      rows=rows.select { |s| s[:category]==q['category'] } if q['category'].present? && q['category']!='全部'
      rows=rows.select { |s| s[:business_status]==q['status'] } if %w[open closed].include?(q['status'])
      text=Shared.text(q['q'] || q['search'],200,required:false).downcase
      if text.present?
        dish_ids=Dish.where(status:'visible').where('name ILIKE :q OR body ILIKE :q',q:"%#{ActiveRecord::Base.sanitize_sql_like(text)}%").pluck(:shop_id)
        rows=rows.select { |s| [s[:name],s[:body],s[:street],s[:category]].compact.any? { |v| v.downcase.include?(text) } || dish_ids.include?(s[:id]) }
      end
      ranges={1=>[nil,10],2=>[10,20],3=>[20,30],4=>[30,50],5=>[50,nil]};range=ranges[q['price'].to_i] || [nil,nil]
      min=range[0] || numeric(q['min_price'],min:0);max=range[1] || numeric(q['max_price'],min:0)
      rows=rows.select { |s| [s[:price_min],s[:price_max]].compact.any? { |p| p>=min } } if min
      rows=rows.select { |s| [s[:price_min],s[:price_max]].compact.any? { |p| p<=max } } if max
      rating=numeric(q['min_rating'],min:0,max:5);rows=rows.select { |s| s[:rating] && s[:rating]>=rating } if rating && rating>0
      case q['sort']
      when 'price-asc' then rows.sort_by { |s| [s[:price_min] ? 0 : 1,s[:price_min] || 0,s[:id]] }
      when 'price-desc' then rows.sort_by { |s| [s[:price_max] ? 1 : 0,-(s[:price_max] || 0),s[:id]] }
      when 'rating-desc' then rows.sort_by { |s| [-(s[:rating] || -1),s[:id]] }
      when 'newest' then rows.sort_by { |s| [-s[:created_at].to_f,-s[:id]] }
      else rows
      end
    end
    def self.entry(item,user)
      kind=item.class.name.demodulize;reactions=Reaction.where(target_kind:kind,target_id:item.id);write=Access.member?(user) && !SiteSetting.food_read_only
      out={id:item.id,kind:kind,body:item.body,author:Shared.author(item.user_id),created_at:item.created_at,images:Shared.media_urls(item.media_ids),likes:reactions.where(value:1).count,liked:user && reactions.exists?(user_id:user.id,value:1),mine:user&.id==item.user_id,can_write:write,can_delete:write && (item.user_id==user.id || Access.admin?(user)),can_manage:write && Access.admin?(user),url:url(item),missing_media_count:item.missing_media_count}
      if item.is_a?(Comment)
        parent=Comment.find_by(id:item.parent_id,target_kind:item.target_kind,target_id:item.target_id);out.merge!(target_kind:item.target_kind,target_id:item.target_id,rating:item.rating&.to_f,tags:item.tags,parent_id:item.parent_id,parent:parent ? {id:parent.id,author:Shared.author(parent.user_id),body:parent.status=='visible' ? parent.body.truncate(160) : '这条评论已隐藏或删除'} : nil)
      else out.merge!(name:item.name,price:item.price&.to_f,tag:item.tag,tag_label:DISH_TAGS[item.tag] || '校友推荐');end
      out
    end
    def self.comments_for(item,user,q)
      scope=Comment.where(target_kind:item.class.name.demodulize,target_id:item.id,status:'visible').to_a
      entries=scope.to_h { |c| [c.id,entry(c,user)] };roots=scope.select { |c| !c.parent_id || !entries.key?(c.parent_id) }
      likes=Reaction.where(target_kind:'Comment',target_id:scope.map(&:id),value:1).group(:target_id).count
      roots=case q['comments_sort'];when 'oldest' then roots.sort_by { |c| [c.created_at,c.id] };when 'likes' then roots.sort_by { |c| [-likes.fetch(c.id,0),-c.created_at.to_f,-c.id] };else roots.sort_by { |c| [-c.created_at.to_f,-c.id] };end
      filter=q['comments_filter'];roots=roots.select do |c|
        case filter;when 'photos' then c.media_ids.any?;when 'good' then c.tags.include?('好吃');when 'cheap' then c.tags.include?('便宜');when 'warning' then c.tags.include?('踩雷');when 'liked' then likes.fetch(c.id,0)>0;else true;end
      end
      children=scope.group_by(&:parent_id)
      flatten=->(c,depth,seen) do
        return [] if seen.include?(c.id)
        seen=seen+[c.id];[entries.fetch(c.id).merge(depth:[depth,4].min)]+Array(children[c.id]).sort_by { |x| q['comments_sort']=='oldest' ? [x.created_at.to_f,x.id] : q['comments_sort']=='likes' ? [-likes.fetch(x.id,0),-x.created_at.to_f,-x.id] : [-x.created_at.to_f,-x.id] }.flat_map { |x| flatten.call(x,depth+1,seen) }
      end
      if q['reply'].present?
        target=scope.find { |c| c.id==q['reply'].to_i };seen=[]
        while target && target.parent_id && entries[target.parent_id] && !seen.include?(target.id);seen<<target.id;target=scope.find { |c| c.id==target.parent_id };end
        index=target && roots.index(target);q=q.merge('page'=>index/20+1) if index
      end
      selected,paging=pagination(roots,q)
      [selected.flat_map { |c| flatten.call(c,0,[]) },paging]
    end
    def self.shop_snapshot(s)
      {name:s.name,area:s.area,category:s.category,body:s.body,business_status:s.business_status,status_reason:s.status_reason,media_ids:s.media_ids,street:s.details['street'],price_min:s.details['price_min'],price_max:s.details['price_max'],latitude:s.details['latitude'],longitude:s.details['longitude']}.deep_stringify_keys
    end
    def self.shop_fields(shop=nil,admin:false)
      value=shop ? shop_snapshot(shop) : {};f=[Ui.field('name','店名',value['name'],required:true,maxlength:120),Ui.field('area','区域',value['area'],type:'select',options:(AREAS+[value['area']]).compact.uniq,required:true),Ui.field('category','分类',value['category'],type:'select',options:[['','未分类']]+(CATEGORIES+[value['category']]).compact.uniq),Ui.field('street','街道地址',value['street'],maxlength:120),Ui.field('price_min','最低人均',value['price_min'],type:'number'),Ui.field('price_max','最高人均',value['price_max'],type:'number'),Ui.field('body','门店介绍',value['body'],type:'textarea',maxlength:4000),Ui.field('business_status','营业状态',value['business_status'] || 'open',type:'select',options:[['open','营业中'],['closed','暂停营业']]),Ui.field('status_reason','暂停原因',value['status_reason'],maxlength:300),Ui.field('latitude','纬度',value['latitude'],type:'number'),Ui.field('longitude','经度',value['longitude'],type:'number')]
      f+=[Ui.field('review','原始推荐语',shop&.review,type:'textarea',maxlength:4000),Ui.field('base_rating','基础评分',shop&.base_rating,type:'number'),Ui.field('source_url','原始来源链接',shop&.details&.[]('source_url'),maxlength:1000)] if admin
      f<<{name:'retain_media_ids',label:'保留门店图片',type:'existing_images',images:shop.media_ids.map { |id| {id:id,url:"/food/media/#{id}"} }} if shop && shop.media_ids.any?
      f<<Ui.field('images','添加图片',nil,type:'upload');f
    end
    def self.comment_form(item,parent:nil)
      fields=[Ui.field('body',parent ? '回复内容' : '你的体验','',type:'textarea',required:true,maxlength:1200)]
      if item.is_a?(Shop) && !parent
        fields+=[Ui.field('rating','评分','',type:'select',options:[['','暂不评分']]+(2..10).map { |n| [(n/2.0).to_s,"#{n/2.0} 星"] }),Ui.field('tags','体验标签',[],type:'checks',options:REVIEW_TAGS),Ui.field('images','配图',nil,type:'upload')]
      end
      Ui.form(parent ? '回复点评' : '写下你的点评','comment',fields,{kind:item.class.name.demodulize,id:item.id,parent_id:parent},button:parent ? '发布回复' : '发布点评')
    end
    def self.proposal_card(p,user)
      shop=Shop.find_by(id:p.shop_id);snapshot=shop && shop_snapshot(shop);changes=p.proposed_changes
      diffs=changes.keys.select { |k| p.before_snapshot[k]!=changes[k] }.map { |k| {field:k,before:p.before_snapshot[k],after:changes[k],current:snapshot&.[](k),conflict:snapshot && snapshot[k]!=p.before_snapshot[k] && snapshot[k]!=changes[k]} }
      {id:p.id,title:changes['name'],status:p.status,shop_id:p.shop_id,author:Shared.author(p.user_id),reason:p.reason,review_reason:p.review_reason,created_at:p.created_at,reviewed_at:p.reviewed_at,images:Shared.media_urls(changes['media_ids']),diffs:diffs,stale:shop && p.base_version!=shop.lock_version,review_version:shop&.lock_version,missing_media_count:p.missing_media_count,url:shop && url(shop)}
    end
    def self.contributors
      rows=Shop.where(status:'visible').where.not(user_id:nil).group(:user_id).pluck(:user_id,Arel.sql('COUNT(*)'),Arel.sql('MAX(created_at)'))
      rows.sort_by { |id,count,latest| [-count,-latest.to_f,id] }.each_with_index.map do |(id,count,latest),index|
        {id:id,rank:index+1,author:Shared.author(id),shop_count:count,latest_contribution:latest}
      end
    end
    def self.state(user,q)
      Access.read!(user);view=q['view'].presence || 'discover';write=Access.member?(user) && !SiteSetting.food_read_only
      tabs=[['discover','发现'],['shops','全部店铺'],['favorites','收藏'],['contribute','一起完善'],['about','关于']];tabs<<['admin','管理'] if Access.admin?(user)
      out={view:view,member:!!Access.member?(user),admin:!!Access.admin?(user),readonly:SiteSetting.food_read_only,tabs:tabs.map { |id,label| {id:id,label:label} },forms:[],shops:[],q:q}
      case view
      when 'discover','shops','favorites'
        all=catalog(user);rows=filter(all,q);out[:stats]={shops:all.length,comments:Comment.where(status:'visible').count,dishes:Dish.where(status:'visible').count}
        out[:areas]=(['全部']+AREAS+(all.map { |s| s[:area] }.uniq-AREAS)).map { |name| {name:name,count:name=='全部' ? all.length : all.count { |s| s[:area]==name }} }
        out[:modes]=MODES.map { |id,label| {id:id,label:label} };out[:categories]=CATEGORIES
        if view=='discover'
          seed=q['seed'].to_s.match?(/\A\d{1,16}\z/) ? q['seed'].to_i : Time.current.in_time_zone('Asia/Shanghai').beginning_of_day.to_i
          out[:seed]=seed;rows=discover(rows,q['mode'],seed)
        elsif view=='favorites'
          ids=Access.member?(user) ? Favorite.where(user_id:user.id).pluck(:shop_id) : q['ids'].to_s.split(',').first(500).map(&:to_i)
          rows=rows.select { |s| ids.include?(s[:id]) }
        end
        out[:shops],out[:pagination]=pagination(rows,q)
      when 'shop'
        shop=visible!(Shop.find(Shared.id(q['id'])),user,admin:true);all=catalog(user,include_hidden:Access.admin?(user));out[:shop]=all.find { |s| s[:id]==shop.id };out[:part]=%w[overview dishes reviews photos history].include?(q['part']) ? q['part'] : 'overview'
        out[:can_write]=write && shop.status=='visible';out[:can_manage]=write && Access.admin?(user)
        comments=Comment.where(target_kind:'Shop',target_id:shop.id,status:'visible').to_a;dishes=Dish.where(shop_id:shop.id,status:'visible').to_a
        out[:dishes]=dishes.map { |d| entry(d,user) }.sort_by { |d| q['dishes_sort']=='newest' ? [-d[:created_at].to_f,-d[:id]] : [-d[:likes],-d[:created_at].to_f,-d[:id]] }
        out[:comments],out[:pagination]=comments_for(shop,user,q)
        out[:gallery]=[{label:'门店照片',images:Shared.media_urls(shop.media_ids)},{label:'菜品照片',images:Shared.media_urls(dishes.flat_map(&:media_ids))},{label:'校友实拍',images:Shared.media_urls(comments.flat_map(&:media_ids))}]
        out[:history]=Proposal.where(shop_id:shop.id,status:'approved').map { |p| {id:"proposal-#{p.id}",author:Shared.author(p.user_id),body:p.reason,created_at:p.reviewed_at || p.updated_at} }+dishes.map { |d| {id:"dish-#{d.id}",author:Shared.author(d.user_id),body:"添加菜品「#{d.name}」",created_at:d.created_at} }
        out[:history]<<{id:'created',author:Shared.author(shop.user_id),body:'收录了这家门店',created_at:shop.created_at} if shop.user_id
        out[:history].sort_by! { |r| -r[:created_at].to_f }
        out[:related]=all.select { |s| s[:id]!=shop.id && s[:area]==shop.area && s[:status]=='visible' }.sort_by { |s| -(s[:rating] || -1) }.first(3)
        out[:comment_form]=comment_form(shop) if write
        out[:dish_form]=Ui.form('推荐一道菜','dish',[Ui.field('name','菜品名称',nil,required:true,maxlength:80),Ui.field('price','价格',nil,type:'number'),Ui.field('tag','推荐程度','must',type:'select',options:DISH_TAGS.to_a),Ui.field('body','推荐理由',nil,type:'textarea',maxlength:600),Ui.field('images','菜品图片',nil,type:'upload')],{shop_id:shop.id},button:'发布菜品',max_images:3) if write
      when 'contribute','edit'
        Access.check!(user);shop=view=='edit' ? visible!(Shop.find(Shared.id(q['id'])),user,admin:true) : nil
        if write
          direct=shop && Access.admin?(user);fields=shop_fields(shop,admin:direct)+[Ui.field('reason',shop ? '修改说明' : '补充说明',nil,required:!!shop,maxlength:500)]
          out[:forms]=[Ui.form(shop ? '完善门店资料' : '推荐一家新店',direct ? 'save_shop' : 'propose',fields,{shop_id:shop&.id,base_version:shop&.lock_version},button:direct ? '保存门店' : '提交审核',max_images:shop ? 16 : 10)]
        end
        rows=Proposal.where(user_id:user.id).order(created_at: :desc,id: :desc).to_a;selected,out[:pagination]=pagination(rows,q);out[:proposals]=selected.map { |p| proposal_card(p,user) }
      when 'about'
        out[:contributors]=contributors
        about=AboutPage.first;out[:about_updated_at]=about&.updated_at;visible!(about,user,admin:true) if about;out[:about_html]=PrettyText.cook(about&.body || '觅电 · 校友共建的美食指南')
        if about
          out[:comments],out[:pagination]=comments_for(about,user,q);out[:comment_form]=comment_form(about) if write
        end
      when 'admin'
        Access.check!(user,admin:true);out[:part]=q['part'].presence || 'proposals'
        case out[:part]
        when 'proposals'
          scope=Proposal.all;scope=scope.where(before_snapshot:{}) if q['proposal_kind']=='new';scope=scope.where.not(before_snapshot:{}) if q['proposal_kind']=='edit';scope=scope.where(status:q['status'].presence || 'pending') unless q['status']=='all';rows,paging=pagination(scope.order(created_at: :desc,id: :desc).to_a,q);out[:pagination]=paging;out[:proposals]=rows.map { |p| proposal_card(p,user) }
        when 'shops'
          rows,paging=pagination(catalog(user,include_hidden:true),q);out[:shops]=rows;out[:pagination]=paging
        when 'comments'
          rows,paging=pagination(Comment.order(created_at: :desc,id: :desc).to_a,q);out[:comments]=rows.map { |c| entry(c,user).merge(status:c.status) };out[:pagination]=paging
        when 'reports'
          rows,paging=pagination(Report.where(handled_at:nil).order(created_at: :desc).to_a,q);out[:reports]=rows.map { |r| r.as_json(only:%i[id target_kind target_id reason created_at]).merge('url'=>url(targets.fetch(r.target_kind).find(r.target_id))) };out[:pagination]=paging
        when 'identities'
          out[:identities]=HistoricalIdentity.order(:id).map { |i| {id:i.id,name:i.username,linked:!!i.linked_user_id,linked_author:i.linked_user_id ? Shared.author(i.linked_user_id) : nil} }
        when 'audits'
          rows,paging=pagination(Audit.order(created_at: :desc).to_a,q);out[:audits]=rows.map { |a| {id:a.id,action:a.action,reason:a.reason,actor:Shared.author(a.user_id),created_at:a.created_at} };out[:pagination]=paging
        when 'about'
          out[:forms]=[Ui.form('编辑关于页面','save_about',[Ui.field('body','Markdown 正文',AboutPage.first&.body,type:'textarea',maxlength:20000)],button:'保存介绍')] if write
        end
      else raise Error,'页面不存在'
      end
      out
    end
    def self.proposal_data(user,data,shop,max:16)
      min=numeric(data['price_min'],min:0,max:1_000_000);max_price=numeric(data['price_max'],min:0,max:1_000_000)
      raise Error,'最低人均不能大于最高人均' if min && max_price && min>max_price
      status=data['business_status'].presence || 'open';raise Error,'无效营业状态' unless %w[open closed].include?(status)
      existing=shop ? (data.key?('retain_media_ids') ? Array(data['retain_media_ids']).map { |id| Shared.id(id) } : shop.media_ids) : []
      raise Error,'不能引用其他门店的图片' if shop && (existing-shop.media_ids).any?
      images=(existing+Shared.media_ids(user,data['media_ids'],max:max)).uniq;raise Error,"最多 #{max} 张图片" if images.size>max
      {name:Shared.text(data['name'],120),area:Shared.text(data['area'],24),category:Shared.text(data['category'],40,required:false).presence,body:Shared.text(data['body'],4000,required:false).presence,street:Shared.text(data['street'],120,required:false).presence,price_min:min,price_max:max_price,business_status:status,status_reason:status=='closed' ? Shared.text(data['status_reason'],300,required:false).presence || '暂停营业' : nil,latitude:numeric(data['latitude'],min:-90,max:90),longitude:numeric(data['longitude'],min:-180,max:180),media_ids:images}.deep_stringify_keys
    end
    def self.apply_shop(shop,values)
      values=values.stringify_keys;details=shop.details.dup
      old_status=shop.business_status
      if shop.new_record? || details['price_min']!=values['price_min'] || details['price_max']!=values['price_max']
        details['price_text']=[values['price_min'],values['price_max']].compact.map { |n| n.to_f==n.to_i ? n.to_i.to_s : n.to_s }.join('-').presence
      end
      %w[street price_min price_max latitude longitude].each { |k| details[k]=values[k] }
      if values['business_status']!=old_status
        details[values['business_status']=='closed' ? 'closed_at' : 'reopened_at']=Time.current.iso8601
      end
      shop.assign_attributes(values.slice('name','area','category','body','business_status','status_reason','media_ids').merge('details'=>details));shop
    end
    def self.call(user,operation,data)
      Access.check!(user);Access.writable!;authorize!(user,operation)
      case operation
      when 'favorite'
        s=visible!(Shop.find(Shared.id(data['id'])),user);Shared.lock("favorite:#{user.id}:#{s.id}")
        scope=Favorite.where(user_id:user.id,shop_id:s.id);scope.exists? ? scope.delete_all : scope.create!;{}
      when 'comment'
        klass={'Shop'=>Shop,'AboutPage'=>AboutPage}[data['kind']];raise Error,'只能点评门店或回复关于页面' unless klass
        item=visible!(klass.lock.find(Shared.id(data['id'])),user);parent=data['parent_id'].present? ? Comment.find(Shared.id(data['parent_id'])) : nil
        raise Error,'回复不属于当前讨论' if parent && (parent.target_kind!=data['kind'] || parent.target_id!=item.id || parent.status!='visible')
        rating=!parent && item.is_a?(Shop) ? numeric(data['rating'],min:1,max:5) : nil
        tags=!parent && item.is_a?(Shop) ? Array(data['tags']).map(&:to_s).select { |t| REVIEW_TAGS.include?(t) }.uniq : []
        raise Error,'最多选择六个标签' if tags.length>6
        c=Comment.create!(user_id:user.id,target_kind:data['kind'],target_id:item.id,parent_id:parent&.id,body:Shared.text(data['body'],1200),rating:rating,tags:tags,media_ids:parent || !item.is_a?(Shop) ? [] : Shared.media_ids(user,data['media_ids'],max:6))
        ([parent&.user_id,item.user_id].compact.uniq-[user.id]).each { |uid| Shared.notify(uid,'你的觅电内容有新的回复',url(c),key:"comment:#{c.id}:#{uid}") }
        {message:'点评已发布',query:item.is_a?(Shop) ? {view:'shop',id:item.id,part:'reviews',reply:c.id} : {view:'about',reply:c.id}}
      when 'dish'
        shop=visible!(Shop.lock.find(Shared.id(data['shop_id'])),user)
        tag=data['tag'].presence;raise Error,'无效的菜品标签' if tag && !DISH_TAGS.key?(tag)
        d=Dish.create!(shop_id:shop.id,user_id:user.id,name:Shared.text(data['name'],80),body:Shared.text(data['body'],600,required:false),price:numeric(data['price'],min:0,max:1_000_000),tag:tag,media_ids:Shared.media_ids(user,data['media_ids'],max:3))
        {message:'菜品已发布',query:{view:'shop',id:shop.id,part:'dishes'}}
      when 'react','report','delete_own','moderate'
        klass=targets[data['kind']];raise Error,'无效内容类型' unless klass
        item=klass.lock.find(Shared.id(data['id']))
        if operation=='moderate'
          status=data['status'];raise Error,'无效状态' unless %w[visible hidden deleted].include?(status)
          Shared.audit(user,status,item,data['reason']);item.update!(status:status)
          Shared.notify(item.user_id,'你的觅电内容有新的管理处理',url(item),key:"moderate:#{item.class.name}:#{item.id}:#{item.updated_at.to_f}") if item.user_id!=user.id
          return {message:'处理已保存'}
        end
        if operation=='delete_own'
          raise Discourse::InvalidAccess unless [Comment,Dish].include?(klass) && (item.user_id==user.id || Access.admin?(user))
          item.update!(status:'deleted',body:'这条内容已删除',media_ids:[]);return {message:'内容已删除'}
        end
        visible!(item,user)
        if operation=='react'
          raise Error,'只能为点评和菜品点赞' unless [Comment,Dish].include?(klass)
          value=Integer(data['value'].to_s);raise Error,'无效反馈' unless [0,1].include?(value)
          scope=Reaction.where(user_id:user.id,target_kind:data['kind'],target_id:item.id);value==0 ? scope.delete_all : scope.first_or_initialize.update!(value:1)
          Shared.notify(item.user_id,'你的觅电内容收到新的赞',url(item),key:"like:#{data['kind']}:#{item.id}:#{user.id}") if value==1 && item.user_id!=user.id
          {}
        else
          reason=Shared.text(data['reason'],500);r=Report.find_or_initialize_by(user_id:user.id,target_kind:data['kind'],target_id:item.id)
          r.update!(reason:reason,handled_at:nil) if r.new_record? || r.handled_at
          {message:'举报已提交'}
        end
      when 'resolve_report'
        report=Report.lock.find(Shared.id(data['id']));report.update!(handled_at:Time.current);Shared.audit(user,'resolve_report',report,'举报已处理');Shared.notify(report.user_id,'你的觅电举报已处理','/food',key:"report:#{report.id}:#{report.created_at.to_f}");{message:'举报已处理'}
      when 'propose','save_shop'
        shop=data['shop_id'].present? ? visible!(Shop.lock.find(Shared.id(data['shop_id'])),user,admin:operation=='save_shop') : nil
        raise Error,'门店已经更新，请重新打开编辑页面' if shop && Integer(data.fetch('base_version'))!=shop.lock_version
        values=proposal_data(user,data,shop,max:shop ? 16 : 10);before=shop ? shop_snapshot(shop) : {}
        if operation=='save_shop'
          raise Error,'门店不存在' unless shop
          source=Shared.safe_url(data['source_url']);raise Error,'来源链接须为 HTTP 或 HTTPS' if data['source_url'].present? && !source
          apply_shop(shop,values);shop.review=Shared.text(data['review'],4000,required:false).presence;shop.base_rating=numeric(data['base_rating'],min:0.5,max:5);shop.details=shop.details.merge('source_url'=>source);shop.save!
          Shared.audit(user,'shop_updated',shop,data['reason'],{before:before,after:shop_snapshot(shop)})
          return {message:'门店资料已保存',query:{view:'shop',id:shop.id}}
        end
        raise Error,'没有检测到资料变化' if shop && values==before
        Proposal.create!(user_id:user.id,shop_id:shop&.id,base_version:shop&.lock_version,before_snapshot:before,proposed_changes:values,reason:Shared.text(data['reason'],500,required:!!shop).presence || '推荐一家新店')
        {message:'已提交审核',query:{view:'contribute'}}
      when 'review_proposal'
        p=Proposal.lock.find(Shared.id(data['id']));raise Error,'申请已处理' unless p.status=='pending'
        reason=Shared.text(data['reason'],500);shop=p.shop_id ? Shop.lock.find(p.shop_id) : nil
        if data['decision']=='approve'
          raise Error,'门店已删除，不能采纳修改' if shop && shop.status!='visible'
          if shop
            raise Error,'审核期间门店已更新，请刷新对照内容' unless Integer(data.fetch('review_version'))==shop.lock_version
            raise Error,'该申请基于旧资料，请核对冲突并明确确认' if p.base_version!=shop.lock_version && !Shared.bool(data['accept_conflicts'])
            delta=p.proposed_changes.reject { |k,v| p.before_snapshot[k]==v };values=shop_snapshot(shop).merge(delta)
          else
            shop=Shop.new(user_id:p.user_id);values=p.proposed_changes
          end
          apply_shop(shop,values);shop.save!
          p.update!(status:'approved',shop_id:shop.id,reviewer_id:user.id,review_reason:reason,reviewed_at:Time.current)
        elsif data['decision']=='reject'
          p.update!(status:'rejected',reviewer_id:user.id,review_reason:reason,reviewed_at:Time.current)
        else raise Error,'无效审核结果';end
        Shared.audit(user,p.status,p,reason);Shared.notify(p.user_id,p.status=='approved' ? '你的觅电贡献已被采纳' : '你的觅电贡献未被采纳','/food?view=contribute',key:"proposal:#{p.id}:#{p.status}");{message:'审核结果已保存'}
      when 'save_about'
        page=AboutPage.first || AboutPage.new(user_id:user.id);page.update!(body:Shared.text(data['body'],20000));Shared.audit(user,'about_updated',page,'更新关于觅电');{message:'介绍已保存'}
      when 'link_identity'
        identity=HistoricalIdentity.lock.find(Shared.id(data['id']));raise Error,'旧账号已经关联' if identity.linked_user_id
        raise Error,'请先核实旧账号与论坛账号属于同一人' unless Shared.bool(data['verified'])
        target=User.find_by(username_lower:Shared.text(data['username'],120).downcase);raise Error,'论坛账号不存在' unless target && target.id>0
        reason=Shared.text(data['reason'],500);UserLifecycle.transfer(identity.virtual_user_id,target.id)
        identity.update!(linked_user_id:target.id);Shared.audit(user,'identity_linked',identity,reason,{target_user_id:target.id});{message:'旧账号的内容已关联到核实后的论坛账号'}
      else raise Error,'未知操作'
      end
    rescue JSON::ParserError
      raise Error,'JSON 格式无效'
    end
    def self.media_allowed?(user,item)
      return true if user && (item.user_id==user.id || Access.admin?(user))
      return true if Shop.where(status:'visible').where('media_ids @> ?',[item.id].to_json).exists?
      return true if Dish.where(status:'visible',shop_id:Shop.where(status:'visible').select(:id)).where('media_ids @> ?',[item.id].to_json).exists?
      Comment.where(status:'visible').where('media_ids @> ?',[item.id].to_json).any? { |c| begin;visible!(c,user);true;rescue Discourse::InvalidAccess,ActiveRecord::RecordNotFound;false;end }
    end
    def self.legacy_query(path,params={})
      q=params.to_h.slice('area','category','price','status','sort');q['q']=params['search'] if params['search'];q['min_price']=params['minPrice'] if params['minPrice'];q['max_price']=params['maxPrice'] if params['maxPrice'];q['min_rating']=params['minRating'] if params['minRating']
      if path.start_with?('shops/')
        row=Legacy.find_by(source:'Shop',legacy_id:path.split('/')[1]);return row ? {view:'shop',id:row.target_id,comments_sort:params['commentSort'],comments_filter:params['commentFilter'],dishes_sort:params['dishSort']}.compact : {view:'shops'}
      end
      if path=='about'
        return {view:'admin',part:'about'} if params['mode']=='edit'
        return {view:'about',comments_sort:params['sort'].presence || 'newest'}
      end
      if path=='admin'
        part={'shops'=>'shops','comments'=>'comments'}.fetch(params['tab'],'proposals')
        kind={'submissions'=>'new','edits'=>'edit'}[params['tab']]
        return {view:'admin',part:part,proposal_kind:kind}.compact
      end
      q.merge(view:{'shops'=>'shops','favorites'=>'favorites','submit'=>'contribute','about'=>'about','admin'=>'admin'}.fetch(path,'discover'))
    end
  end
end
