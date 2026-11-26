# Health Library: article management, comments and reply notifications

## What's new

1. **Admin article management.** Admin overview has a new **Health Library articles** entry, where admins can:
   - **Add** an article: title, summary, content, health condition, source name and link, and an optional image link. Tapping **Add article** (or **Save changes**) opens a dialog with **Publish** or **Save as draft**.
   - **Health condition** is picked from the conditions already in the database (Admin > Conditions, `chronic_conditions`). "Other" isn't offered. An article keeps its condition even if that condition is later deactivated.
   - **View** an article the way members see it, with its status, likes and comments.
   - **Edit** any field, or switch an article between Draft and Published. The first publish date is kept.
   - **Delete** an article. Its likes, saves and comments are deleted with it.
   - **Publish / Move to drafts** straight from the article page, without opening the editor. Moving to drafts asks for confirmation. Publishing needs a source.
   - **Moderate comments:** delete any comment.
2. **Comments.** Help seekers and approved volunteers can comment on published articles. Accounts that are restricted, and volunteers who are still pending, can't comment.
3. **Replies.** Members can reply to any comment. A reply to a reply goes into the same thread, labelled "Replying to <name>". Members can delete their own comments. A deleted comment with no replies disappears. If it has replies, it shows as "This comment was deleted" (text and author removed) and the replies stay. When the last reply goes, the placeholder goes too. The comment box sits under the comments.
4. **Reply notifications.** When someone replies to your comment, you get a notification (kind `article_reply`). The title is the replier's name and the article title (`Sara replied on "Living with diabetes"`); the body is the reply text. It shows in the notification list and the in-app banner, and arrives as a push through the existing `maak_notification_push` trigger. Tapping it opens the article and scrolls to the comments. Replying to your own comment sends nothing.

Article cards in the Health Library show the article photo (the https image link) and a comment count, and the whole card opens the article. The photo also shows on the article page.

**Health Library layout (help seekers and volunteers):** **Filter & sort** sits beside the search bar and opens as a dropdown menu (sort order, health condition from the database, clear filters). The All / Saved / Liked chips are replaced by a **My articles** menu (Saved articles, Liked articles) next to the section title.

**Other changes:** the required star after "I agree to AI matching." on registration is red. On the volunteer home page, **View requests** and the **Requests** quick action switch to the Requests tab, like Messages does.

## Database setup

Run in the Supabase SQL editor, after the account-blocking and push-notification migrations:

```
supabase/migrations/20261126000000_article_management_comments.sql
```

- You can run it more than once.
- **Already ran an earlier copy of this file?** Run it again. It moves articles from `illness_types` to `chronic_conditions` by matching names (and aliases). Any article whose old tag has no matching condition becomes General, and the SQL editor prints how many.
- **Error 23502 when saving an article?** Your `articles` table has NOT NULL on a column the app leaves empty (for example the old `illness_type_id`). Re-running the migration removes NOT NULL from the optional columns (`illness_type_id`, `source_name`, `source_url`, `image_url`, `published_at`) and from any other required column the app never fills. The SQL editor lists each column it changed.
- It creates `articles`, `illness_types`, `article_likes` and `saved_articles` only if they don't exist yet. Existing rows and policies are left as they are.
- All admin writes and all comment access go through security-definer RPCs, so the migration doesn't depend on the policies already on `articles`. The `article_comments` table can't be read or written by clients directly.
- Limits: comments can be 1–1000 characters, with at most 5 comments per member per minute. A published article needs a source name and an http(s) link.

Rollback: `supabase/rollbacks/20261126000000_article_management_comments_rollback.sql`. This removes comments and the new RPCs, and keeps the articles.

## Tests

```
cd tests/database && npm install && node article_comments_test.mjs
```

53 checks run twice: once against fresh tables, and once against production-like tables (existing policies, foreign keys without cascade).

## Changed files

- New: `lib/backend/services/article_admin_service.dart`, `lib/frontend/patient/article_comments.dart`, `lib/frontend/redesign/admin_articles.dart` (part of `admin.dart`), the migration, the rollback and the test.
- Updated: `ai_consent.dart` (red star), `home.dart` (Requests buttons switch tab), `health_library_service.dart` (comments, comment counts, conditions from `chronic_conditions`), `health_library_page.dart` (comments section, Filter & sort dropdown, My articles menu; `ArticleDetailsPage` is now public), `admin.dart` (overview entry), `notifications.dart` and `shell.dart` (open the article on tap), `feedback.dart` (error messages), `push_notification_service.dart` (comment only).
