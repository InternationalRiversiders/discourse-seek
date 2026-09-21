import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import dIcon from "discourse/ui-kit/helpers/d-icon";
export default class extends Component {
  <template>
    <article class="food-shop">
      <a class="food-shop-cover" href={{@shop.url}} {{on "click" @visit}}>
        {{#if @shop.cover}}<img src={{@shop.cover}} alt={{@shop.name}} loading="lazy" />{{else}}<span class="food-no-photo">{{dIcon "utensils"}}<small>等你来晒美食</small></span>{{/if}}
        {{#if (eq @shop.business_status "closed")}}<span class="food-closed">暂停营业</span>{{/if}}
      </a>
      <div class="food-shop-content">
        <div class="food-eyebrow">{{@shop.area}}{{#if @shop.category}} · {{@shop.category}}{{/if}}</div>
        <div class="food-shop-title"><h3><a href={{@shop.url}} {{on "click" @visit}}>{{@shop.name}}</a></h3><button class="btn no-text btn-flat food-favorite {{if @shop.favorite 'is-active'}}" title={{if @shop.favorite "取消收藏" "收藏店铺"}} aria-label={{if @shop.favorite "取消收藏" "收藏店铺"}} aria-pressed={{if @shop.favorite "true" "false"}} {{on "click" (fn @favorite @shop)}}>{{dIcon "heart"}}</button></div>
        <div class="food-shop-score"><span class="food-rating">{{dIcon "star"}} {{if @shop.rating @shop.rating "暂无评分"}}</span><span>{{@shop.price}}</span><span>{{@shop.comments_count}} 条点评</span></div>
        {{#if @shop.latest_comment}}<p class="food-shop-excerpt">“{{@shop.latest_comment}}”</p>{{else}}<p class="food-shop-excerpt">{{@shop.body}}</p>{{/if}}
        <div class="food-tags">{{#each @shop.review_tags as |tag|}}<span>{{tag.tag}} {{tag.count}}</span>{{/each}}</div>
        {{#if @shop.recommended_dishes}}<p class="food-recommended">推荐：{{#each @shop.recommended_dishes as |name|}}<span>{{name}} </span>{{/each}}</p>{{/if}}
      </div>
    </article>
  </template>
}
