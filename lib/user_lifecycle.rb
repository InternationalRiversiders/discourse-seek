# frozen_string_literal: true
module DiscourseSeek
  module UserLifecycle
    def self.transfer(source,target)
      return if source==target
      Record.transaction do
        [source,target].sort.each { |id| Shared.lock("user:#{id}") }
        Reaction.where(user_id:source).find_each do |r|
          duplicate=Reaction.find_by(user_id:target,target_kind:r.target_kind,target_id:r.target_id)
          if duplicate
            Legacy.where(target_kind:'Reaction',target_id:r.id).update_all(target_id:duplicate.id);r.destroy!
          else r.update!(user_id:target);end
        end
        [Favorite,Report].each do |klass|
          klass.where(user_id:source).find_each do |r|
            keys=klass==Favorite ? {shop_id:r.shop_id} : {target_kind:r.target_kind,target_id:r.target_id}
            klass.exists?(keys.merge(user_id:target)) ? r.destroy! : r.update!(user_id:target)
          end
        end
        [Shop,Dish,Comment,Proposal,Media].each { |klass| klass.where(user_id:source).update_all(user_id:target) }
        Proposal.where(reviewer_id:source).update_all(reviewer_id:target)
        Legacy.where(target_kind:'User',target_id:source).update_all(target_id:target)
        HistoricalIdentity.where(virtual_user_id:source).each { |i| Legacy.where(source:'User',legacy_id:i.legacy_id).update_all(target_kind:'User',target_id:target) }
        HistoricalIdentity.where(linked_user_id:source).update_all(linked_user_id:target)
        Command.where(user_id:source).delete_all;Event.where(user_id:source).delete_all
      end
    end
    def self.purge(id,erase_content:true)
      return unless Shop.table_exists?
      Record.transaction do
        Shared.lock("user:#{id}");replacement=-2_000_000_000-id
        local_ids=Legacy.where(source:'User').where("(target_kind='User' AND target_id=?) OR data->>'providerUserKey'=?",id,"discourse:#{id}").pluck(:legacy_id)
        local_ids+=HistoricalIdentity.where(linked_user_id:id).pluck(:legacy_id)
        Legacy.where(source:'User',legacy_id:local_ids).delete_all
        if local_ids.any?
          Legacy.where("data->>'userId' IN (?)",local_ids).delete_all
          Legacy.where("data->>'submitterId' IN (:ids) OR data->>'reviewerId' IN (:ids)",ids:local_ids).find_each { |r| r.update!(data:r.data.merge('submitterId'=>nil,'reviewerId'=>nil)) }
        end
        HistoricalIdentity.where(linked_user_id:id).delete_all
        [Reaction,Report,Favorite,Command,Event].each { |klass| klass.where(user_id:id).delete_all }
        Legacy.where(target_kind:'Proposal',target_id:Proposal.where(user_id:id).select(:id)).delete_all
        Proposal.where(user_id:id).delete_all
        Proposal.where(reviewer_id:id).update_all(reviewer_id:nil)
        Audit.where(user_id:id).update_all(user_id:Discourse.system_user.id)
        Audit.where("details->>'target_user_id'=?",id.to_s).update_all(details:{})
        Shop.where(user_id:id).update_all(user_id:nil)
        [Comment,Dish].each do |klass|
          ids=klass.where(user_id:id).pluck(:id);Legacy.where(target_kind:klass.name.demodulize,target_id:ids).delete_all
          attrs={user_id:replacement};attrs.merge!(body:'内容已随账号删除',status:'deleted',media_ids:[],missing_media_count:0) if erase_content
          klass.where(user_id:id).update_all(attrs)
        end
        if erase_content
          media_ids=Media.where(user_id:id).pluck(:id)
          if media_ids.any?
            [Shop,Dish,Comment].each do |klass|
              klass.where('EXISTS(SELECT 1 FROM jsonb_array_elements_text(media_ids) m(value) WHERE m.value IN (?))',media_ids.map(&:to_s)).find_each { |row| row.update!(media_ids:row.media_ids-media_ids) }
            end
            Proposal.find_each do |p|
              changes=p.proposed_changes;before=p.before_snapshot
              p.update!(proposed_changes:changes.merge('media_ids'=>Array(changes['media_ids'])-media_ids),before_snapshot:before.merge('media_ids'=>Array(before['media_ids'])-media_ids)) if (Array(changes['media_ids'])&media_ids).any? || (Array(before['media_ids'])&media_ids).any?
            end
          end
          Media.where(user_id:id).delete_all
        else Media.where(user_id:id).update_all(user_id:replacement);end
        Notification.where(user_id:id,notification_type:Notification.types[:custom]).where("data::jsonb->>'river_app'='food'").destroy_all
      end
    end
  end
end
DiscourseEvent.on(:user_destroyed) { |user| DiscourseSeek::UserLifecycle.purge(user.id) }
DiscourseEvent.on(:user_anonymized) { |user:,**_| DiscourseSeek::UserLifecycle.purge(user.id,erase_content:false) }
DiscourseEvent.on(:merging_users) { |source,target| DiscourseSeek::UserLifecycle.transfer(source.id,target.id) if DiscourseSeek::Shop.table_exists? }
