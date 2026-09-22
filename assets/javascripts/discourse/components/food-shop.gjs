import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import dIcon from "discourse/ui-kit/helpers/d-icon";
export default class extends Component {
  <template>
    <article class="food-shop {{if (eq @shop.business_status 'closed') 'is-closed'}}">
      <a class="food-shop-cover" href={{@shop.url}} {{on "click" @visit}}>
        {{#if @shop.cover}}<img src={{@shop.cover}} alt={{@shop.name}} loading="lazy" />{{else}}<span class="food-no-photo">{{dIcon "utensils"}}<small>等你来晒美食</small></span>{{/if}}
        {{#if (eq @shop.business_status "closed")}}<span class="food-closed">暂停营业</span>{{/if}}
      </a>
      <div class="food-shop-content">
        <div class="food-shop-title"><h3><a href={{@shop.url}} {{on "click" @visit}}>{{@shop.name}}</a></h3><button type="button" class="btn no-text btn-flat food-favorite {{if @shop.favorite 'is-active'}}" title={{if @shop.favorite "取消收藏" "收藏店铺"}} aria-label={{if @shop.favorite "取消收藏" "收藏店铺"}} aria-pressed={{if @shop.favorite "true" "false"}} {{on "click" (fn @favorite @shop)}}>{{dIcon "heart"}}</button></div>
        <div class="food-shop-score"><span class="food-rating {{unless @shop.rating 'is-unrated'}}">{{dIcon "star"}} {{if @shop.rating @shop.rating "暂无评分"}}</span><span>{{@shop.comments_count}} 条点评</span></div>
        <p class="food-shop-price">{{#if (eq @shop.price "价格未知")}}<span>人均待补充</span>{{else}}<strong>{{@shop.price}}</strong><span>/ 人均</span>{{/if}}</p>
        <p class="food-shop-location">{{dIcon "location-dot"}} <span>{{@shop.area}}{{#if @shop.category}} · {{@shop.category}}{{/if}}{{#if @shop.street}} · {{@shop.street}}{{/if}}</span></p>
        {{#if @shop.latest_comment}}<p class="food-shop-excerpt is-review">{{dIcon "comment"}}<span>“{{@shop.latest_comment}}”</span></p>{{else if @shop.body}}<p class="food-shop-excerpt"><span>{{@shop.body}}</span></p>{{/if}}
        {{#if @shop.review_tags.length}}<div class="food-tags">{{#each @shop.review_tags as |tag|}}<span>{{tag.tag}} <small>{{tag.count}}</small></span>{{/each}}</div>{{/if}}
        {{#if @shop.recommended_dishes.length}}<p class="food-recommended"><span class="food-dish-label">推荐菜</span><span class="food-dish-names">{{#each @shop.recommended_dishes as |name|}}<span>{{name}}</span>{{/each}}</span></p>{{/if}}
      </div>
    </article>
  </template>
}
