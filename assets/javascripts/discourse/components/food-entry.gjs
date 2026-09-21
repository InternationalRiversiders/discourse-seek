import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import DRelativeDate from "discourse/ui-kit/d-relative-date";
const depthClass = (depth) => depth ? "food-entry is-reply" : "food-entry";
export default class extends Component {
  <template>
    <article class={{depthClass @entry.depth}} id="food-reply-{{@entry.id}}">
      <div class="food-avatar" aria-hidden="true">{{dIcon (if (eq @entry.kind "Dish") "utensils" "comment")}}</div>
      <div class="food-entry-content">
        <header>{{#if @entry.author.url}}<a href={{@entry.author.url}}>{{@entry.author.name}}</a>{{else}}<strong>{{@entry.author.name}}</strong>{{/if}}{{#if @entry.author.historical}}<small>历史署名</small>{{/if}}<a href={{@entry.url}} {{on "click" @visit}}><DRelativeDate @date={{@entry.created_at}} /></a>{{#if @entry.rating}}<span class="food-rating">{{dIcon "star"}} {{@entry.rating}}</span>{{/if}}</header>
        {{#if @entry.name}}<h3>{{@entry.name}} <small>{{@entry.tag_label}}{{#if @entry.price}} · ¥{{@entry.price}}{{/if}}</small></h3>{{/if}}
        {{#if @entry.parent}}<blockquote>回复 {{@entry.parent.author.name}}：{{@entry.parent.body}}</blockquote>{{/if}}
        <p class="food-body">{{@entry.body}}</p>
        <div class="food-tags">{{#each @entry.tags as |tag|}}<span>{{tag}}</span>{{/each}}</div>
        <div class="food-photos">{{#each @entry.images as |url|}}<button type="button" {{on "click" (fn @photo url)}} aria-label="放大图片"><img src={{url}} alt="校友实拍" loading="lazy" /></button>{{/each}}</div>
        {{#if @entry.missing_media_count}}<small class="food-muted">{{@entry.missing_media_count}} 张历史图片已缺失</small>{{/if}}
        <footer><button class="btn btn-flat {{if @entry.liked 'is-active'}}" disabled={{if @busy true (unless @entry.can_write true)}} aria-label="点赞" {{on "click" (fn @react @entry)}}>{{dIcon "heart"}} {{@entry.likes}}</button>
          {{#if @entry.can_write}}{{#if (eq @entry.kind "Comment")}}<button class="btn btn-flat" {{on "click" (fn @reply @entry)}}>{{dIcon "comment"}} 回复</button>{{/if}}<button class="btn btn-flat" {{on "click" (fn @report @entry)}}>{{dIcon "flag"}} 举报</button>{{/if}}
          {{#if @entry.can_delete}}<button class="btn btn-flat" {{on "click" (fn @remove @entry)}}>{{dIcon "trash-can"}} 删除</button>{{/if}}
          {{#if @entry.can_manage}}<button class="btn btn-flat" {{on "click" (fn @moderate @entry)}}>管理{{#if @entry.status}} · {{@entry.status}}{{/if}}</button>{{/if}}
        </footer>
      </div>
    </article>
  </template>
}
