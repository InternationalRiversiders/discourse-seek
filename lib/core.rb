# frozen_string_literal: true
require 'digest'
require 'vips'
module DiscourseSeek
  class Error < StandardError; end
  class Record < ActiveRecord::Base; self.abstract_class=true; end
  %w[Command Event Audit Legacy Media Reaction Report Comment HistoricalIdentity].each do |name|
    klass=Class.new(Record);klass.table_name=name=='Media' ? 'river_food_media' : "river_food_#{name.underscore.pluralize}";const_set(name,klass)
  end
  module Access
    def self.admin?(user) = user && user.active? && !user.suspended? && (user.admin? || user.in_any_groups?(SiteSetting.food_admin_groups.split('|').map(&:to_i)))
    def self.member?(user) = user && user.active? && !user.suspended? && (admin?(user) || user.in_any_groups?(SiteSetting.food_allowed_groups.split('|').map(&:to_i)))
    def self.read!(user)
      raise Discourse::InvalidAccess unless SiteSetting.food_enabled && (!SiteSetting.food_admin_only || admin?(user)) && (SiteSetting.food_public_browse || member?(user))
    end
    def self.check!(user,admin:false)
      read!(user);raise Discourse::InvalidAccess unless admin ? admin?(user) : member?(user)
    end
    def self.writable!
      raise Error,'当前为只读预览，暂不接受修改' if SiteSetting.food_read_only
    end
  end
  module Shared
    def self.text(value,max=4000,required:true)
      v=value.to_s.strip;raise Error,'请填写必填内容' if required && v.empty?;raise Error,"内容超过 #{max} 字限制" if v.length>max;v
    end
    def self.id(value)
      n=Integer(value.to_s,10) rescue nil;raise Error,'无效编号' unless n && n>0;n
    end
    def self.bool(v) = v==true || %w[true 1 on].include?(v.to_s)
    def self.lock(key) = Record.connection.execute("SELECT pg_advisory_xact_lock(#{Digest::SHA256.digest("river_food:#{key}").unpack1('q>')})")
    def self.canonical(v)
      case v;when Hash then v.keys.map(&:to_s).sort.to_h { |k| [k,canonical(v[k])] };when Array then v.map { |x| canonical(x) };else v;end
    end
    def self.command(user,operation,data,key)
      Access.check!(user);Access.writable!;Service.authorize!(user,operation)
      raise Error,'请求编号缺失' unless key.to_s.match?(/\A[\w-]{8,100}\z/)
      fingerprint=Digest::SHA256.hexdigest([operation,canonical(data)].to_json)
      Record.transaction do
        lock("user:#{user.id}");lock("command:#{user.id}:#{key}")
        old=Command.find_by(user_id:user.id,key:key)
        if old;raise Error,'请求编号已用于其他操作' unless old.fingerprint==fingerprint;next old.result;end
        result=yield || {};Command.create!(user_id:user.id,key:key,fingerprint:fingerprint,result:result);result
      end
    end
    def self.audit(actor,action,item,reason,details={})
      Audit.create!(user_id:actor.id,action:action,target_kind:item.class.name.demodulize,target_id:item.id,reason:text(reason,500),details:details)
    end
    def self.notify(uid,text,path,key:)
      return unless uid && uid>0 && User.exists?(uid)
      Event.create_or_find_by!(key:key) { |e| e.user_id=uid;e.text=text;e.path=path }
    end
    def self.deliver
      return unless SiteSetting.food_enabled && !SiteSetting.food_read_only
      Event.where(notification_id:nil).order(:id).limit(100).each do |event|
        event.with_lock do
          next if event.notification_id || !Access.member?(User.find_by(id:event.user_id))
          n=Notification.create!(user_id:event.user_id,notification_type:Notification.types[:custom],skip_send_email:true,data:{river_app:'food',river_text:event.text,river_path:event.path,river_icon:'utensils',message:'food',display_username:'',topic_title:event.text}.to_json)
          event.update!(notification_id:n.id)
        end
      rescue => e
        Rails.logger.warn("food notification #{event.id}: #{e.class}")
      end
    end
    def self.author(uid)
      if uid && uid>0 && (u=User.find_by(id:uid))
        {name:u.username,url:"/u/#{u.username_lower}",historical:false}
      elsif uid && (u=HistoricalIdentity.find_by(virtual_user_id:uid))
        {name:u.username,historical:true}
      else
        {name:'校友',historical:false}
      end
    end
    def self.user_name(uid) = author(uid)[:name]
    def self.image(bytes)
      head=bytes.byteslice(0,12)
      valid=head&.start_with?("\xFF\xD8\xFF".b,"\x89PNG\r\n\x1A\n".b,'GIF87a','GIF89a') || (head&.start_with?('RIFF') && head.byteslice(8,4)=='WEBP')
      raise Error,'只支持 JPEG、PNG、GIF 或 WebP 图片' unless valid
      image=Vips::Image.new_from_buffer(bytes,'',access: :sequential);raise Error,'图片尺寸过大' if image.width*image.height>30_000_000
      image=image.autorot;image=image.flatten(background:[255,255,255]) if image.has_alpha?;image=image.copy_memory
      [[1200,78],[1200,55],[800,70],[800,50]].each do |side,quality|
        ratio=[side.to_f/image.width,side.to_f/image.height,1].min;out=(ratio<1 ? image.resize(ratio) : image).jpegsave_buffer(Q:quality,strip:true);return out if out.bytesize<=1.megabyte
      end
      raise Error,'压缩后图片超过 1MB'
    end
    def self.media_ids(user,values,max:16)
      ids=Array(values).map { |v| id(v) }.uniq;raise Error,"最多 #{max} 张图片" if ids.size>max
      raise Error,'图片不属于你或已不存在' unless Media.where(id:ids,user_id:user.id).count==ids.size;ids
    end
    def self.media_urls(ids) = Array(ids).map { |id| "/food/media/#{id}" }
    def self.safe_url(value)
      uri=URI.parse(value.to_s);uri.to_s if %w[http https].include?(uri.scheme) && uri.host.present? && !uri.userinfo
    rescue URI::InvalidURIError
      nil
    end
  end
  class MainController < ::ApplicationController
    requires_plugin 'discourse-seek'
    skip_before_action :check_xhr, only:[:index,:media,:legacy,:export]
    skip_before_action :redirect_to_login_if_required, only:[:index,:state,:media,:legacy]
    before_action :enabled!
    rescue_from Error,ArgumentError do |e| render_json_dump({errors:[e.message]},status:422);end
    def index
      Access.read!(current_user);response.headers['Cache-Control']='private, no-store';render 'default/empty'
    end
    def state
      Access.read!(current_user);response.headers['Cache-Control']='private, no-store';render_json_dump(Service.state(current_user,params.to_unsafe_h))
    end
    def mutate
      Access.check!(current_user);Access.writable!;RateLimiter.new(current_user,'food-write',40,1.minute).performed!
      data=params.fetch(:data,ActionController::Parameters.new).permit!.to_h
      result=Shared.command(current_user,params.require(:operation).to_s,data,params.require(:request_id)) { Service.call(current_user,params[:operation].to_s,data) }
      Shared.deliver;response.headers['Cache-Control']='private, no-store';render_json_dump(result)
    end
    def upload
      Access.check!(current_user);Access.writable!;RateLimiter.new(current_user,'food-upload',30,1.hour).performed!
      file=params.require(:file);raise Error,'图片最大 10MB' unless file.respond_to?(:tempfile) && file.size.between?(1,10.megabytes)
      bytes=Shared.image(File.binread(file.tempfile.path))
      item=Record.transaction do
        Shared.lock("media:#{current_user.id}");raise Error,'图片空间已达 50MB' if Media.where(user_id:current_user.id).sum(:size)+bytes.bytesize>50.megabytes
        Media.create!(user_id:current_user.id,bytes:bytes,size:bytes.bytesize,token:SecureRandom.hex(24))
      end
      render_json_dump({id:item.id,url:"/food/media/#{item.id}"})
    rescue Vips::Error
      render_json_dump({errors:['无法处理此图片']},status:422)
    end
    def media
      Access.read!(current_user);item=Media.find(params[:id]);raise Discourse::InvalidAccess unless Service.media_allowed?(current_user,item)
      response.headers['Cache-Control']='private, no-store';response.headers['X-Content-Type-Options']='nosniff';send_data(item.bytes,type:'image/jpeg',disposition:'inline')
    end
    def legacy
      redirect_to('/food?'+Service.legacy_query(params[:path].to_s,params).to_query,allow_other_host:false)
    end
    def export
      Access.check!(current_user);response.headers['Cache-Control']='private, no-store';send_data(JSON.pretty_generate(UserLifecycle.export(current_user.id)),type:'application/json',filename:'my-food-data.json')
    end
    private
    def enabled!;raise Discourse::NotFound unless SiteSetting.food_enabled;end
  end
  module Ui
    def self.field(name,label,value=nil,type:'text',options:nil,required:false,maxlength:nil)
      {name:name,label:label,value:value,type:type,required:required,maxlength:maxlength,options:options&.map { |v| v.is_a?(Array) ? {value:v[0],label:v[1]} : {value:v,label:v} }}
    end
    def self.form(title,operation,fields,data={},button:'保存',max_images:6)
      {title:title,operation:operation,fields:fields,data:data,button:button,max_images:max_images}
    end
  end
end
module ::Jobs
  class DiscourseSeekTick < ::Jobs::Scheduled
    every 1.minute
    def execute(args)
      return unless SiteSetting.food_enabled && !SiteSetting.food_read_only
      DistributedMutex.synchronize('food-tick') { DiscourseSeek::Shared.deliver }
    end
  end
end
