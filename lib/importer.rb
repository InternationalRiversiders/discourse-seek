# frozen_string_literal: true
require 'digest'
module DiscourseSeek
  class Importer
    def initialize(payload, directory: nil, allow_missing_media: false)
      @payload=payload;@tables=payload.fetch('tables');@directory=directory;@allow_missing_media=allow_missing_media;@media_cache={};@users={};@historical=[];@missing=[]
      raise Error,'导出文件格式或项目不符' unless payload['format']=='riverside-community-v1' && payload['project']=='seek'
    end
    def rows(name) = @tables[name] || []
    def ref(name,id,optional:false)
      return nil if id.nil? && optional
      value=Legacy.find_by(source:name,legacy_id:id.to_s)&.target_id
      raise Error,"缺少关联：#{name}/#{id}" unless value || optional
      value
    end
    def local_user(id,optional:false)
      return nil if id.nil? && optional
      @users.fetch(id.to_s) { raise Error,"本地用户不存在：#{id}" }
    end
    def stamp(row)
      created=row['createdAt'] || row['updatedAt'] || @payload['exported_at']
      {created_at:Time.iso8601(created),updated_at:Time.iso8601(row['updatedAt'] || row['reviewedAt'] || created)}
    end
    def put(source,row,klass,attrs)
      item=klass.create!(stamp(row).merge(attrs))
      Legacy.find_by!(source:source,legacy_id:row.fetch('id',row['key']).to_s).update!(target_kind:klass.name.demodulize,target_id:item.id)
      item
    end
    def image_names(values)
      values=JSON.parse(values) if values.is_a?(String)
      Array(values)
    end
    def missing_count(values)
      image_names(values).count { |n| @payload['media'].any? { |m| m['name']==n && m['missing'] } }
    end
    def images(values,uid)
      image_names(values).filter_map do |name|
        next @media_cache[name] if @media_cache.key?(name)
        entry=Array(@payload['media']).find { |m| m['name']==name }
        raise Error,'缺少图片清单' unless entry
        if entry['missing']
          raise Error,'旧图片已缺失；核对清单后显式允许缺图导入' unless @allow_missing_media
          @missing<<name unless @missing.include?(name);@media_cache[name]=nil;next
        end
        raise Error,'缺少图片目录' unless @directory
        root=File.realpath(@directory);path=File.realpath(File.join(root,entry.fetch('file')))
        raise Error,'图片路径越界' unless path.start_with?(root+'/')
        raw=File.binread(path);raise Error,'图片校验和不符' unless Digest::SHA256.hexdigest(raw)==entry['sha256']
        bytes=Shared.image(raw)
        media=Media.create!(user_id:uid || Discourse.system_user.id,token:SecureRandom.hex(24),bytes:bytes,size:bytes.bytesize)
        @media_cache[name]=media.id
      end
    end
    def run(sha:,apply:false,expected_sha:nil)
      raise Error,'正式导入需要匹配的 SHA256' if apply && sha!=expected_sha
      raise Error,'正式导入前请关闭插件' if apply && SiteSetting.food_enabled
      result=nil
      Record.transaction do
        Shared.lock('legacy-import')
        existing=Legacy.find_by(source:'__manifest',legacy_id:sha)
        if existing;result={already_imported:true,sha256:sha,counts:existing.data['counts']};next;end
        tables=ActiveRecord::Base.connection.tables.grep(/\Ariver_food_/)
        occupied=tables.any? { |table| Record.connection.select_value("SELECT EXISTS(SELECT 1 FROM #{Record.connection.quote_table_name(table)})") }
        raise Error,'目标插件已有业务数据，请使用空的隔离目标演练' if occupied
        @tables.each do |source,records|
          raise Error,'记录列表无效' unless records.is_a?(Array)
          records.each { |row| Legacy.create!(source:source,legacy_id:row.fetch('id',row['key']).to_s,data:row) }
        end
        rows('User').each do |r|
          key=r['providerUserKey'].to_s;id=key.match(/\Adiscourse:(\d+)\z/)&.[](1)&.to_i
          if id && User.exists?(id)
            @users[r['id'].to_s]=id
            Legacy.find_by!(source:'User',legacy_id:r['id'].to_s).update!(target_kind:'User',target_id:id)
          else
            # Historical authors are data only: no User, login, credential or OAuth endpoint is created.
            virtual=-1_000_000_000-Integer(r['id'].to_s,10)
            identity=HistoricalIdentity.create!(legacy_id:r['id'].to_s,virtual_user_id:virtual,username:r['username'].presence || '历史校友')
            @users[r['id'].to_s]=virtual;@historical<<r['id']
            Legacy.find_by!(source:'User',legacy_id:r['id'].to_s).update!(target_kind:'HistoricalIdentity',target_id:identity.id)
          end
        end
        import_domain
        counts=tables.to_h { |table| [table,Record.connection.select_value("SELECT COUNT(*) FROM #{Record.connection.quote_table_name(table)}").to_i] }
        result={sha256:sha,apply:apply,source_counts:@tables.transform_values(&:size),counts:counts,historical_accounts:@historical.size,missing_media:@missing.size,media_mapping:@media_cache}
        Legacy.create!(source:'__manifest',legacy_id:sha,data:result)
        Record.connection.reset_pk_sequence!(Shop.table_name)
        Record.connection.execute('SET CONSTRAINTS ALL IMMEDIATE')
        raise ActiveRecord::Rollback unless apply
      end
      result
    end
    def proposal_snapshot(r,uid,fallback:{})
      keys={'name'=>'name','area'=>'area','category'=>'category','description'=>'body','status'=>'business_status','statusReason'=>'status_reason','street'=>'street','priceMin'=>'price_min','priceMax'=>'price_max','latitude'=>'latitude','longitude'=>'longitude'}
      out=fallback.deep_dup
      keys.each { |old,new_key| out[new_key]=r[old] if r.key?(old) }
      out['business_status']||='open';out['media_ids']=images(r['images'],uid) if r.key?('images')
      out
    end
    def import_domain
      rows('Shop').each do |r|
        uid=local_user(r['submitterId'],optional:true)
        put('Shop',r,Shop,{id:Integer(r['id'].to_s,10),user_id:uid,name:r['name'],area:r['area'],category:r['category'],business_status:r['status']=='closed' ? 'closed' : 'open',status_reason:r['statusReason'],body:r['description'],review:r['review'],base_rating:r['rating'],details:{street:r['street'],price_min:r['priceMin'],price_max:r['priceMax'],price_text:r['priceText'],source_url:r['sourceUrl'],latitude:r['latitude'],longitude:r['longitude'],closed_at:r['closedAt'],reopened_at:r['reopenedAt']},media_ids:images(r['images'],uid),missing_media_count:missing_count(r['images'])})
      end
      rows('Dish').each do |r|
        uid=local_user(r['submitterId'],optional:true);body,tag=Service.parse_dish(r['description'])
        put('Dish',r,Dish,{user_id:uid,shop_id:ref('Shop',r['shopId']),name:r['name'],body:body,tag:tag,price:r['price'],media_ids:images(r['images'],uid),missing_media_count:missing_count(r['images'])})
      end
      config=rows('SiteConfig').find { |r| r['key']=='about' } || rows('SiteConfig').first
      about=config ? put('SiteConfig',config,AboutPage,{body:config['value']}) : AboutPage.create!(body:'觅电 · 校友一起完善的美食指南')
      [['Comment','Shop'],['AboutComment','AboutPage']].each do |source,kind|
        pending=rows(source).dup
        until pending.empty?
          progress=false
          pending.delete_if do |r|
            next false if r['parentId'] && !Legacy.find_by(source:source,legacy_id:r['parentId'].to_s)&.target_id
            uid=local_user(r['userId']);body,tags=Service.parse_review(r['content'])
            put(source,r,Comment,{user_id:uid,target_kind:kind,target_id:kind=='Shop' ? ref('Shop',r['shopId']) : about.id,parent_id:r['parentId'] ? ref(source,r['parentId']) : nil,body:body,tags:tags,rating:r['rating'],media_ids:images(r['images'],uid),missing_media_count:missing_count(r['images'])})
            progress=true;true
          end
          raise Error,'评论父子关系有缺失或循环' unless progress
        end
      end
      [['CommentLike','Comment','commentId'],['AboutCommentLike','AboutComment','commentId'],['DishLike','Dish','dishId']].each do |source,target,key|
        rows(source).each do |r|
          dest=Legacy.find_by!(source:target,legacy_id:r[key].to_s)
          put(source,r,Reaction,{user_id:local_user(r['userId']),target_kind:dest.target_kind,target_id:dest.target_id,value:1})
        end
      end
      rows('ShopSubmission').each do |r|
        uid=local_user(r['submitterId'],optional:true)
        put('ShopSubmission',r,Proposal,{user_id:uid,status:r['status'] || 'pending',proposed_changes:proposal_snapshot(r.except('status'),uid),reason:'迁移前的新店申请',missing_media_count:missing_count(r['images'])})
      end
      rows('ShopEditSubmission').each do |r|
        uid=local_user(r['submitterId'],optional:true);shop=Shop.find(ref('Shop',r['shopId']));changes=JSON.parse(r['changes']);before=r['beforeSnapshot'].present? ? JSON.parse(r['beforeSnapshot']) : {}
        baseline=proposal_snapshot(before,uid,fallback:Service.shop_snapshot(shop));normalized=proposal_snapshot(changes,uid,fallback:baseline)
        put('ShopEditSubmission',r,Proposal,{user_id:uid,reviewer_id:local_user(r['reviewerId'],optional:true),shop_id:shop.id,base_version:r['status']=='pending' ? -1 : shop.lock_version,status:r['status'] || 'pending',before_snapshot:baseline,proposed_changes:normalized,reason:r['summary'].presence || '迁移前的资料修改',reviewed_at:r['reviewedAt'],missing_media_count:(image_names(changes['images'])+image_names(before['images'])).uniq.count { |n| @media_cache.key?(n) && @media_cache[n].nil? }})
      end
    end
  end
end
