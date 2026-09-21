# frozen_string_literal: true
abort 'Disposable test database only' unless ENV['RIVER_DISPOSABLE']=='1' && GlobalSetting.db_name=='river_community_test'
require 'minitest/autorun'
class SeekTest < Minitest::Test
  A=DiscourseSeek
  def setup
    tables=A::Record.connection.tables.grep(/\Ariver_food_/)
    A::Record.connection.execute('TRUNCATE '+tables.map { |t| A::Record.connection.quote_table_name(t) }.join(',')+' RESTART IDENTITY CASCADE')
    @group=Group.find_or_create_by!(name:'food_test_members')
    @admin=make_user('food_admin',true);@alice=make_user('food_alice');@bob=make_user('food_bob');@outsider=make_user('food_outsider')
    [@alice,@bob].each { |u| @group.add(u);u.reload }
    SiteSetting.food_enabled=true;SiteSetting.food_read_only=false;SiteSetting.food_admin_only=false;SiteSetting.food_public_browse=true;SiteSetting.food_allowed_groups=@group.id.to_s;SiteSetting.food_admin_groups=''
    @shop=A::Shop.create!(name:'测试面馆',area:'南门',body:'热汤面',user_id:@alice.id,base_rating:3,details:{'price_min'=>10,'price_max'=>20})
    A::AboutPage.create!(body:'共建美食指南')
  end
  def make_user(name,admin=false)
    user=User.find_by(username:name) || User.create!(username:name,email:"#{name}@example.com",password:SecureRandom.hex(30),active:true,approved:true,admin:admin)
    user.update!(admin:admin,active:true,suspended_till:nil);user
  end
  def call(user,op,data={},key:SecureRandom.uuid)
    A::Shared.command(user,op,data.deep_stringify_keys,key) { A::Service.call(user,op,data.deep_stringify_keys) }
  end
  def state(user=@alice,**q) = A::Service.state(user,q.deep_stringify_keys)
  def comment(user=@bob,**data)
    A::Comment.find(call(user,'comment',{kind:'Shop',id:@shop.id,body:'好吃的面',rating:5,tags:['好吃']}.merge(data))[:query][:reply])
  end
  def test_access_readonly_idempotence_rechecked
    assert_equal 1,state(nil)[:shops].length
    assert_raises(Discourse::InvalidAccess) { call(@outsider,'comment',{kind:'Shop',id:@shop.id,body:'x'}) }
    key=SecureRandom.uuid;data={kind:'Shop',id:@shop.id,body:'x'}
    call(@alice,'comment',data,key:key);call(@alice,'comment',data,key:key);assert_equal 1,A::Comment.count
    SiteSetting.food_read_only=true;assert_raises(A::Error) { call(@alice,'comment',data,key:key) }
    assert_empty state(view:'shop',id:@shop.id)[:comment_form].to_a
    SiteSetting.food_admin_only=true;assert_raises(Discourse::InvalidAccess) { state(@alice) };assert state(@admin)[:admin]
    SiteSetting.food_admin_only=false;SiteSetting.food_public_browse=false;assert_raises(Discourse::InvalidAccess) { state(nil) }
  end
  def test_rating_tags_replies_filters_and_deleted_parent
    c=comment;reply=comment(@alice,parent_id:c.id,rating:1,tags:['踩雷'])
    assert_nil reply.rating;assert_empty reply.tags;assert_equal 4,state(view:'shop',id:@shop.id)[:shop][:rating]
    assert_equal 2,state(view:'shop',id:@shop.id,comments_filter:'good')[:comments].size
    assert_empty state(view:'shop',id:@shop.id,comments_filter:'warning')[:comments]
    assert_raises(Discourse::InvalidAccess) { call(@alice,'delete_own',{kind:'Comment',id:c.id}) }
    call(@bob,'delete_own',{kind:'Comment',id:c.id});s=state(view:'shop',id:@shop.id)
    assert_equal [reply.id],s[:comments].map { |r| r[:id] };assert_equal 3,s[:shop][:rating]
    assert_equal '这条评论已隐藏或删除',s[:comments][0][:parent][:body]
    assert_raises(A::Error) { comment(rating:0.5) }
  end
  def test_likes_notifications_and_media_privacy
    c=comment;call(@alice,'react',{kind:'Comment',id:c.id,value:1});call(@alice,'react',{kind:'Comment',id:c.id,value:1})
    assert_equal 1,A::Reaction.count
    assert_raises(A::Error) { call(@alice,'react',{kind:'Comment',id:c.id,value:-1}) }
    A::Shared.deliver;assert A::Event.where(user_id:@bob.id).where.not(notification_id:nil).exists?
    m=A::Media.create!(user_id:@alice.id,token:SecureRandom.hex(24),bytes:'x',size:1)
    refute A::Service.media_allowed?(nil,m);assert A::Service.media_allowed?(@alice,m)
    c.update!(media_ids:[m.id]);assert A::Service.media_allowed?(nil,m)
    @shop.update!(status:'hidden');refute A::Service.media_allowed?(@bob,m)
    assert_raises(Discourse::InvalidAccess) { state(@bob,view:'shop',id:@shop.id) }
    assert state(@admin,view:'shop',id:@shop.id)[:can_manage]
    assert_raises(A::Error) { A::Shared.media_ids(@bob,[m.id]) }
  end
  def test_proposals_conflicts_preserve_unrelated_fields
    before=A::Service.shop_snapshot(@shop);payload=before.merge('shop_id'=>@shop.id,'base_version'=>0,'name'=>'新店名','reason'=>'核对门牌')
    call(@bob,'propose',payload);p=A::Proposal.last
    @shop.update!(category:'面食');assert_raises(A::Error) { call(@admin,'review_proposal',{id:p.id,decision:'approve',reason:'核对',review_version:0}) }
    assert_raises(A::Error) { call(@admin,'review_proposal',{id:p.id,decision:'approve',reason:'核对',review_version:@shop.lock_version}) }
    call(@admin,'review_proposal',{id:p.id,decision:'approve',reason:'核对',review_version:@shop.lock_version,accept_conflicts:true})
    assert_equal '新店名',@shop.reload.name;assert_equal '面食',@shop.category;assert_equal 'approved',p.reload.status;assert_equal '核对门牌',p.reason;assert_equal '核对',p.review_reason
    assert_raises(A::Error) { call(@admin,'review_proposal',{id:p.id,decision:'reject',reason:'x'}) }
    assert_raises(Discourse::InvalidAccess) { call(@alice,'save_about',{body:'x'}) }
    call(@alice,'propose',{name:'新店',area:'西门',body:'推荐',reason:'好吃'});n=A::Proposal.last
    call(@admin,'review_proposal',{id:n.id,decision:'approve',reason:'欢迎'});assert_equal @alice.id,A::Shop.find(n.reload.shop_id).user_id
  end
  def test_dishes_favorites_reports_export_and_lifecycle
    call(@alice,'dish',{shop_id:@shop.id,name:'牛肉面',price:18,body:'牛肉多',tag:'must'});d=A::Dish.last
    assert_equal '必点',state(view:'shop',id:@shop.id)[:dishes][0][:tag_label]
    call(@bob,'favorite',{id:@shop.id});assert_equal 1,state(@bob,view:'favorites')[:shops].length
    call(@bob,'report',{kind:'Dish',id:d.id,reason:'测试举报'});r=A::Report.last
    assert_raises(Discourse::InvalidAccess) { state(@bob,view:'admin') };call(@admin,'resolve_report',{id:r.id});assert r.reload.handled_at
    c=comment(@alice);call(@alice,'react',{kind:'Dish',id:d.id,value:1});call(@bob,'react',{kind:'Dish',id:d.id,value:1})
    A::UserLifecycle.transfer(@alice.id,@bob.id);assert_equal @bob.id,d.reload.user_id;assert_equal 1,A::Reaction.count
    assert_equal [c.id],A::UserLifecycle.export(@bob.id)[:comments].map { |x| x['id'] }
    A::UserLifecycle.purge(@bob.id);assert_equal 'deleted',c.reload.status;assert_equal 'deleted',d.reload.status;assert_empty A::Reaction.all;assert_nil @shop.reload.user_id
  end
  def test_search_price_sort_pagination_and_legacy
    24.times { |i| A::Shop.create!(name:"小吃 #{i}",area:'西门',category:'小吃',details:{price_min:i,price_max:i+5}) }
    assert_equal 20,state(view:'shops')[:shops].length;assert_equal 5,state(view:'shops',page:2)[:shops].length
    assert_equal 24,state(view:'shops',q:'小吃')[:pagination][:total]
    assert_equal [@shop.id],state(view:'shops',area:'南门')[:shops].map { |s| s[:id] }
    A::Legacy.create!(source:'Shop',legacy_id:'55',target_kind:'Shop',target_id:@shop.id,data:{})
    assert_equal 'likes',A::Service.legacy_query('shops/55',{'commentSort'=>'likes'})[:comments_sort]
    call(@bob,'import_favorites',{ids:'[55]'});assert_equal 1,A::Favorite.count
    assert_raises(A::Error) { call(@bob,'import_favorites',{ids:'[55,999999]'}) };assert_equal 1,A::Favorite.count
    assert_equal 3,A::Service.tag_summary(A::Comment.where(id:[]).to_a+[A::Comment.new(tags:A::Service::REVIEW_TAGS,parent_id:nil)]).length
  end
  def test_import_preserves_historical_authors_reactions_and_no_login
    A::Record.connection.execute('TRUNCATE '+A::Record.connection.tables.grep(/\Ariver_food_/).join(',')+' RESTART IDENTITY CASCADE')
    now=Time.current.iso8601
    payload={'format'=>'riverside-community-v1','project'=>'seek','exported_at'=>now,'media'=>[],'tables'=>{
      'User'=>[{'id'=>'77','providerUserKey'=>'github:123','username'=>'old_author','createdAt'=>now},{'id'=>'78','providerUserKey'=>"discourse:#{@alice.id}",'username'=>@alice.username,'createdAt'=>now}],
      'Shop'=>[{'id'=>'90','name'=>'旧店铺','area'=>'南门','description'=>'介绍','review'=>'推荐','rating'=>4,'images'=>'[]','submitterId'=>'77','createdAt'=>now,'updatedAt'=>now}],
      'Comment'=>[{'id'=>'5','shopId'=>'90','userId'=>'77','content'=>"好吃\n<!--review-tags:%E5%A5%BD%E5%90%83-->",'rating'=>5,'images'=>'[]','createdAt'=>now}],
      'CommentLike'=>[{'id'=>'1','userId'=>'77','commentId'=>'5','createdAt'=>now}],
      'ShopEditSubmission'=>[{'id'=>'8','shopId'=>'90','submitterId'=>'77','changes'=>{'name'=>'新店名'}.to_json,'beforeSnapshot'=>{'name'=>'旧店铺'}.to_json,'status'=>'pending','createdAt'=>now}]
    }}
    SiteSetting.food_enabled=false;users=User.count;result=A::Importer.new(payload).run(sha:'abc');assert_equal 0,A::Shop.count
    A::Importer.new(payload).run(sha:'abc',apply:true,expected_sha:'abc');assert_equal users,User.count
    assert_equal 1,A::HistoricalIdentity.count;assert_equal 1,A::Reaction.count;assert_empty A::Event.all;assert_equal(-1_000_000_077,A::Comment.first.user_id)
    assert_equal '好吃',A::Comment.first.body;assert_equal ['好吃'],A::Comment.first.tags;assert_equal 'old_author',A::Shared.author(A::Comment.first.user_id)[:name]
    assert_equal(-1,A::Proposal.first.base_version);assert_equal '介绍',A::Shop.find(90).body;assert_equal '推荐',A::Shop.find(90).review
    assert A::Shop.create!(name:'新店',area:'南门').id>90
    assert A::Importer.new(payload).run(sha:'abc',apply:true,expected_sha:'abc')[:already_imported]
  end
end
