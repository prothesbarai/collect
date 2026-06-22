# Pai Entity Chat System — সম্পূর্ণ বাংলা ডকুমেন্টেশন (Schema)

---

## সূচিপত্র

1. [পুরো সিস্টেমটা এক নজরে বোঝা](#overview)
2. [দুটো অ্যাপ, কে কী করে](#two-apps)
3. [টেবিলগুলোর সম্পর্ক — ম্যাপ](#relation-map)
4. [টেবিল ধরে ধরে বিস্তারিত](#tables)
5. [বিজনেস ফ্লো — বাস্তব ঘটনার মতো করে](#flows)
6. [সাবস্ক্রিপশন + লিমিট কীভাবে কাজ করে](#subscription-logic)
7. [মডারেশন — বাজে শব্দ কীভাবে ব্লক হয়](#moderation)
8. [Fiverr-স্টাইল Accepting Dialogue কীভাবে কাজ করে](#fiverr-flow)
9. [ইনডেক্স ও পারফরম্যান্স নোট](#performance)
10. [Go ব্যাকএন্ডে পরবর্তী কাজের ক্রম](#next-steps)

---

<a id="overview"></a>
## ১. পুরো সিস্টেমটা এক নজরে বোঝা

Pai আসলে ৭টা আলাদা মার্কেটপ্লেস — **PaiMart, PaiBazar, PaiB2B, PaiFood, PaiAura, PaiPharma, PaiPlay**। প্রতিটার কাস্টমার আলাদা, মার্চেন্ট আলাদা, নিয়মও আলাদা হতে পারে। পুরো ডাটাবেজে `entity_id` দিয়ে এই বিভাজন রক্ষা করা হয়েছে।

চ্যাট সিস্টেমের মূল দুটো নিয়ম:

- **কাস্টমার** কোনো প্রোডাক্টের পেজ থেকে অথবা মার্চেন্টের প্রোফাইল থেকে চ্যাট শুরু করতে পারবে
- **মার্চেন্ট** তার ড্যাশবোর্ডে শুধু সেই entity-র চ্যাটগুলো দেখবে যে entity সে লগইন করার সময় সিলেক্ট করেছে

এই পুরো জিনিসটা ধরে রাখতে ১৮টা টেবিল আছে।  — এগুলো আসলে ৫টা গ্রুপে ভাগ করলে মাথায় সহজে ঢোকে:

| গ্রুপ | টেবিল | এক কথায় কাজ |
|---|---|---|
| পরিচয় ও প্রোফাইল | entities, users, merchant_profiles, products | কে কোথায়, কার দোকান কোথায় |
| সাবস্ক্রিপশন | subscription_plans, user_subscriptions, entity_chat_settings, daily_chat_usage | কে কতটুকু সুবিধা পাবে |
| চ্যাটের মূল অংশ | chat_rooms, messages, message_attachments, price_offers, contact_share_requests | আসল চ্যাট |
| নিরাপত্তা | bad_keywords, moderation_logs, user_blocks, chat_reports | খারাপ জিনিস আটকানো |
| নোটিফিকেশন | user_devices | অফলাইন ইউজারকে জানানো |

---

<a id="two-apps"></a>
## ২. দুটো অ্যাপ — কে কী করে

### Customer App (কাস্টমার অ্যাপ)
এক অ্যাপের ভেতরে **PaiMart** আর **PaiBazar** দুটো entity দেখা যায়। কাস্টমার entity সুইচ করতে পারে, প্রতিটা entity-র মার্চেন্ট আর প্রোডাক্ট আলাদাভাবে দেখে। চ্যাট শুরু করার দুটো রাস্তা:

```
রাস্তা ১ — প্রোডাক্ট পেজ থেকে:
  কাস্টমার প্রোডাক্ট দেখছে
  → প্রোডাক্টের is_negotiable = TRUE হলে "দাম কমাতে চ্যাট করুন" বাটন দেখাবে
  → বাটনে চাপলে chat_rooms তৈরি হয় (initiation_source = 'product_page', product_id সেট থাকে)

রাস্তা ২ — মার্চেন্ট প্রোফাইল থেকে:
  কাস্টমার মার্চেন্টের স্টোর পেজে গেছে
  → "মেসেজ করুন" বাটনে চাপলে chat_rooms তৈরি হয় (initiation_source = 'merchant_profile', product_id = NULL)
  → পরে চ্যাটের ভেতরে কোনো প্রোডাক্ট নিয়ে কথা হলে price_offer-এ product_id বসানো যাবে
```

### Merchant App (মার্চেন্ট অ্যাপ)
মার্চেন্ট লগইনের সময় প্রথমে **store type** সিলেক্ট করে — যেমন PaiB2B বা PaiAura। এটাই আসলে `entity_id` সিলেক্ট করা। তারপর সেই entity-র email/password দিয়ে লগইন হয়। ড্যাশবোর্ডে শুধু সেই entity-র কাস্টমারদের চ্যাট দেখা যায়। মার্চেন্ট যদি দুটো entity-তে দোকান করে, তাহলে `users` টেবিলে তার দুটো আলাদা রো থাকবে।

---

<a id="relation-map"></a>
## ৩. টেবিলগুলোর সম্পর্ক

```
entities  ──────────────────────────────────────────────┐
  │                                                     │
  ├── entity_chat_settings (প্রতি entity-র chat override) │
  ├── bad_keywords (global বা entity-specific)           │
  ├── subscription_plans (global বা entity-specific)     │
  │                                                     │
  └── users (entity + role মিলিয়ে একটা অ্যাকাউন্ট)       │
        │                                               │
        ├── merchant_profiles ──── store_code (unique ID)
        │       └── products ── is_negotiable (চ্যাট CTA)
        ├── user_subscriptions
        ├── daily_chat_usage (দিনের মেসেজ কাউন্টার)
        ├── user_devices (push token)
        │
        └── chat_rooms ── initiation_source (কোথা থেকে শুরু)
               │
               ├── messages
               │     ├── message_attachments (ছবি/ফাইল — no Firebase)
               │     └── moderation_logs (ব্লক হওয়া মেসেজের প্রমাণ)
               │
               ├── price_offers ── title + description (Fiverr dialogue)
               │     └── previous_offer_id (counter-offer chain)
               ├── contact_share_requests (নাম্বার শেয়ারের অনুমতি-ফ্লো)
               └── chat_reports (অভিযোগ)

user_blocks (যেকোনো দুই ইউজারের মধ্যে, room-নির্ভর না)
```

**সবচেয়ে গুরুত্বপূর্ণ মনে রাখার বিষয়:** সব রাস্তা `chat_rooms` দিয়ে যায়। একটা রুম মানেই একটা কথোপকথন — সেখানেই মেসেজ, ছবি, দামের অফার, সব থাকে।

---

<a id="tables"></a>
## ৪. টেবিল ধরে ধরে বিস্তারিত

---

### ৪.১ `entities` — ৭টা মার্কেটপ্লেসের তালিকা

এই টেবিলে সবসময় মাত্র ৭টা রো থাকবে। পুরো সিস্টেমের ভিত্তি এখান থেকে।

| কলাম | ধরন | কাজ |
|---|---|---|
| `id` | CHAR(36) | UUID — অন্য সব টেবিলে `entity_id` হিসেবে ব্যবহার হয় |
| `name` | VARCHAR(50) | মানুষ-পড়ার জন্য নাম, যেমন "PaiMart" |
| `slug` | VARCHAR(50) UNIQUE | URL-friendly নাম, যেমন `paimart` — API রুটে এটা দিয়েই কোন entity বোঝা যাবে |
| `logo_url` | VARCHAR(255) | অ্যাপে entity-র লোগো দেখানোর জন্য |
| `is_active` | BOOLEAN | FALSE করলে পুরো entity বন্ধ — অ্যাপ লজিকে এটা চেক করতে হবে |

> **নতুন entity যোগ করার প্রয়োজন হলে:** শুধু এই টেবিলে একটা নতুন রো INSERT করলেই হবে। বাকি সব টেবিল `entity_id` দিয়ে অটো কাজ করবে।

---

### ৪.২ `users` — entity-scoped অ্যাকাউন্ট

এটা global user table না। **একই মানুষ দুটো entity-তে দোকান করলে এখানে দুটো আলাদা রো থাকবে।** Merchant App-এ type-select করার পর যে entity-র email/password দিয়ে লগইন হয়, সেটাই এই টেবিলে `(entity_id, email)` দিয়ে ম্যাচ করা হয়।

| কলাম | কাজ |
|---|---|
| `entity_id` | এই অ্যাকাউন্ট কোন marketplace-এর |
| `role` | `customer` / `merchant` / `admin` / `support` — পারমিশন এটার উপর নির্ভর করে |
| `subscription_plan_cache` | দ্রুত পড়ার জন্য ক্যাশ। **আসল সত্য থাকে `user_subscriptions`-এ।** সাবস্ক্রিপশন বদলালে এটাও আপডেট করতে হবে |
| `is_online` | WebSocket hub যখন কানেক্ট পাবে TRUE, ডিসকানেক্ট হলে FALSE — Flutter-এ "Online" ব্যাজের জন্য |
| `last_seen_at` | "Last seen 5 minutes ago" দেখানোর জন্য |
| `deleted_at` | Soft delete — ইউজার ডিলিট হলেও পুরোনো চ্যাট হিস্ট্রি থাকে। কখনো `DELETE FROM users` করবেন না |

**ইউনিক কন্সট্রেইন্ট:** `(entity_id, phone)` এবং `(entity_id, email)` — একই নাম্বার/ইমেইল দুটো আলাদা entity-তে রেজিস্ট্রেশন করা যাবে, কিন্তু একই entity-তে দুইবার না।

---

### ৪.৩ `merchant_profiles` — মার্চেন্টের দোকানের তথ্য

প্রতিটা মার্চেন্ট user-এর জন্য একটা করে স্টোর প্রোফাইল। `entity_id` এখানে `store_type_id`-এর কাজ করে — মার্চেন্ট লগইনের সময় যে type সিলেক্ট করেছে সেটাই।

| কলাম | কাজ |
|---|---|
| `store_code` | **মানুষ-পড়তে পারা ইউনিক স্টোর আইডি**, যেমন `PM-A1B2C3`। এটা Go ব্যাকএন্ড জেনারেট করবে রেজিস্ট্রেশনের সময়। কাস্টমার এই কোড দিয়ে মার্চেন্ট খুঁজতে পারবে |
| `store_slug` | URL-friendly নাম, যেমন `/paimart/store/raju-electronics` — (entity_id + store_slug) মিলে unique |
| `verification_status` | `pending` → অ্যাডমিন approve করলে `verified` বা `rejected` |
| `is_chat_enabled` | এই মার্চেন্টের চ্যাট পলিসি ভঙ্গের কারণে বন্ধ করতে চাইলে FALSE করুন |
| `rating_avg` | কাস্টমারদের রেটিং-এর গড়। চ্যাট accept হওয়ার পর রেটিং দেওয়ার ফিচার থাকলে এটা আপডেট হবে |

---

### ৪.৪ `products` — চ্যাটের জন্য প্রোডাক্ট রেফারেন্স

এটা কোনো পূর্ণ product catalog টেবিল না — শুধু চ্যাট সিস্টেমের দরকারি তথ্য রাখে। আলাদা Product Service থাকলে এই টেবিল বাদ দেওয়া যাবে।

| কলাম | কাজ |
|---|---|
| `is_negotiable` | **🔑 সবচেয়ে গুরুত্বপূর্ণ নতুন কলাম।** TRUE হলে Customer App-এ প্রোডাক্টের পেজে "দাম কমাতে চ্যাট করুন" বাটন দেখাবে। FALSE হলে বাটন দেখাবে না |
| `price` | প্রোডাক্টের আসল দাম — এটা দিয়ে customer আর merchant দুজনেই রেফারেন্স হিসেবে দেখতে পাবে কতটুকু দরকষাকষি হচ্ছে |
| `status` | `active` / `inactive` / `out_of_stock` — স্টক শেষ হলে চ্যাট CTA লুকিয়ে ফেলা উচিত |

**যখন আলাদা Product Service আছে:** `products` টেবিল তখন দরকার নেই। `chat_rooms.product_id` আর `price_offers.product_id` কলাম থেকে FOREIGN KEY সরিয়ে শুধু `CHAR(36)` রাখুন। Go ব্যাকএন্ড Product Service-এ API কল করে প্রোডাক্ট ভ্যালিডেট করবে।

---

### ৪.৫ `subscription_plans` — লিমিটের রুলবুক

এই টেবিলটাই সিদ্ধান্ত নেয় — কোন মার্চেন্ট কতটা মেসেজ পাঠাতে পারবে, ছবি পাঠাতে পারবে কিনা, নাম্বার শেয়ার করতে পারবে কিনা।

| কলাম | কাজ |
|---|---|
| `entity_id` | NULL হলে সব entity-তে কার্যকর। নির্দিষ্ট ID দিলে শুধু সেই entity-তে (যেমন PaiPharma-র জন্য আলাদা বেশি দামের প্ল্যান) |
| `max_messages_per_day` | দিনে সর্বোচ্চ কতটা মেসেজ পাঠানো যাবে |
| `max_images_per_day` | দিনে সর্বোচ্চ কতটা ছবি পাঠানো যাবে |
| `can_send_images` | ছবি পাঠানোর পারমিশন আছে কিনা (এই FALSE থাকলে উপরের কাউন্ট অর্থহীন) |
| `can_share_contact` | ফোন নাম্বার শেয়ার করার পারমিশন আছে কিনা |
| `can_negotiate_price` | দরকষাকষি করতে পারবে কিনা |

**Seed ডেটায় ৩টা প্ল্যান দেওয়া আছে:**

| প্ল্যান | মেসেজ/দিন | ছবি/দিন | ছবি পাঠানো | নাম্বার শেয়ার | দাম |
|---|---|---|---|---|---|
| Free | ২০ | ০ | ❌ | ❌ | বিনামূল্যে |
| Pro | ২০০ | ১০ | ✅ | ❌ | ৳৪৯৯/মাস |
| Premium | ১০০০ | ৫০ | ✅ | ✅ | ৳১৪৯৯/মাস |

---

### ৪.৬ `user_subscriptions` — কে এখন কোন প্ল্যানে

`users` আর `subscription_plans`-এর মধ্যবর্তী লিংক। হিস্ট্রিও রাখে — কেউ প্ল্যান আপগ্রেড করলে পুরোনো রো থেকে যায়, নতুন রো যোগ হয়।

Go ব্যাকএন্ডে যখন মেসেজ পাঠানোর আগে পারমিশন চেক করবেন:
```sql
SELECT sp.*
FROM user_subscriptions us
JOIN subscription_plans sp ON us.plan_id = sp.id
WHERE us.user_id = ?
  AND us.entity_id = ?
  AND us.status = 'active'
  AND (us.expires_at IS NULL OR us.expires_at > NOW())
ORDER BY us.started_at DESC
LIMIT 1;
```
এই কুয়েরির ফলাফল দিয়েই বুঝবেন ইউজার কী কী করতে পারবে।

---

### ৪.৭ `entity_chat_settings` — entity-ভিত্তিক override

প্রতিটা entity-র চ্যাট নিয়ম একটু আলাদা করার সুযোগ। প্ল্যানের উপরে চাপিয়ে দেওয়া যায়।

| কলাম | কাজ |
|---|---|
| `allow_image_attachment_override` | **NULL** = প্ল্যান যা বলে; **TRUE** = প্ল্যান যাই বলুক ছবি পাঠানো যাবে; **FALSE** = প্ল্যান যাই বলুক ছবি বন্ধ (PaiPharma-তে regulation-এর কারণে এটা FALSE করা যেতে পারে) |
| `allow_contact_share_override` | একইভাবে নাম্বার শেয়ারকে override করে |
| `require_product_context` | TRUE করলে কাস্টমার কোনো প্রোডাক্ট ছাড়া সরাসরি মার্চেন্টকে মেসেজ করতে পারবে না (PaiB2B-র জন্য উপযোগী) |
| `auto_close_after_days` | X দিন কোনো কথা না হলে রুম অটো `closed` হয়ে যাবে — একটা Go cron job দিয়ে রাতে চালাবেন |

**পারমিশন চেক করার সঠিক ক্রম:**
```
entity_chat_settings.allow_image_attachment_override
  → NULL?  তাহলে subscription_plans.can_send_images দেখো
  → TRUE?  অনুমতি আছে (প্ল্যান যাই বলুক)
  → FALSE? অনুমতি নেই (প্ল্যান যাই বলুক)
```

---

### ৪.৮ `chat_rooms` — চ্যাটের মূল পাত্র

একটা রুম = একজন কাস্টমার + একজন মার্চেন্টের মধ্যে একটা কথোপকথন।

#### `initiation_source` — v2-তে নতুন, অত্যন্ত গুরুত্বপূর্ণ

| মান | কোথা থেকে শুরু | product_id |
|---|---|---|
| `product_page` | কাস্টমার কোনো negotiable প্রোডাক্টের পেজ থেকে চ্যাট করেছে | ✅ শুরু থেকেই সেট থাকবে |
| `merchant_profile` | কাস্টমার মার্চেন্টের স্টোর প্রোফাইল থেকে মেসেজ করেছে | ❌ শুরুতে NULL, পরে price_offer-এ প্রোডাক্ট যোগ হতে পারে |

**CHECK constraint আছে:**
```sql
CHECK (initiation_source <> 'product_page' OR product_id IS NOT NULL)
```
মানে — যদি `product_page` থেকে চ্যাট শুরু হয়, তাহলে `product_id` অবশ্যই দিতে হবে। ভুলে NULL দিলে ডাটাবেজ নিজেই এরর দেবে।

#### Denormalized ফিল্ডগুলো (যা বারবার জিজ্ঞেস করা হয়)

চ্যাট লিস্ট স্ক্রিনে প্রতিটা রুমের জন্য — শেষ মেসেজ কী ছিল, কতটা অপঠিত আছে — এই তথ্য দরকার। হাজার হাজার রুমের জন্য প্রতিবার `messages` টেবিল স্ক্যান করলে স্লো হবে। তাই এগুলো `chat_rooms`-এ আলাদা রেখে দেওয়া হয়েছে।

| কলাম | কাজ |
|---|---|
| `last_message_id` | শেষ মেসেজের আইডি (FK নেই ইচ্ছাকৃতভাবে — circular dependency এড়াতে) |
| `last_message_at` | শেষ মেসেজের সময় — রুম লিস্ট sort করতে এটা ব্যবহার হয় |
| `last_message_preview` | শেষ মেসেজের প্রথম ২৫৫ অক্ষর — লিস্টে preview দেখানোর জন্য |
| `customer_unread_count` / `merchant_unread_count` | যে পার্টি রিড করেনি তার কাউন্ট — Flutter-এ লাল ব্যাজ দেখানোর জন্য |

⚠️ **সতর্কতা:** নতুন মেসেজ insert করার সময় এই ফিল্ডগুলোও update করতে ভুললে চ্যাট লিস্টে ভুল তথ্য দেখাবে। Go ব্যাকএন্ডে message insert আর room update একটা transaction-এ করুন।

---

### ৪.৯ `messages` — প্রতিটা মেসেজ

| কলাম | কাজ |
|---|---|
| `message_type` | Flutter কীভাবে রেন্ডার করবে সেটা ঠিক করে: `text` = সাধারণ বাবল; `image` = ছবি; `price_offer` = অফার কার্ড; `product_share` = প্রোডাক্ট কার্ড; `contact_request` = নাম্বার-শেয়ার রিকোয়েস্ট কার্ড; `system` = "চ্যাট শুরু হয়েছে" জাতীয় সিস্টেম মেসেজ |
| `content` | মেসেজের লেখা। **ব্লক হলে এখানে আসল লেখা থাকবে না**, placeholder থাকবে — আসল লেখা `moderation_logs.original_content`-এ |
| `moderation_status` | `clean` (ঠিকঠাক) / `flagged` (সন্দেহজনক, রিভিউ করতে হবে) / `blocked` (সরিয়ে ফেলা হয়েছে) |
| `delivery_status` | `sent` → `delivered` → `read` — WebSocket দিয়ে রিয়েলটাইম আপডেট হবে |
| `reply_to_message_id` | কোনো মেসেজের রিপ্লাই হলে আগের মেসেজের আইডি |
| `metadata` | JSON — ভবিষ্যতে দরকার হলে অতিরিক্ত ডেটা রাখার জায়গা (যেমন প্রোডাক্টের স্ন্যাপশট) |
| `deleted_at` | "সবার জন্য ডিলিট" ফিচার — রো মুছে ফেলা হয় না, শুধু টাইমস্ট্যাম্প বসে |

---

### ৪.১০ `message_attachments` — ছবি/ফাইল (Firebase ছাড়া)

Firebase নেই, তাই Go ব্যাকএন্ড নিজেই ফাইল হ্যান্ডেল করে।

| কলাম | কাজ |
|---|---|
| `storage_provider` | `local` / `minio` / `s3` — শুরুতে local disk, পরে MinIO-তে শিফট করলে শুধু এই ভ্যালু বদলাবে, টেবিল একই থাকবে |
| `storage_path` | ডিস্কে বা bucket-এ ফাইলের লোকেশন, যেমন `paimart/room-abc/uuid.jpg` |
| `file_url` | Flutter যে URL দিয়ে ছবি দেখাবে। Go-এ `/media/` রুট দিয়ে serve হবে |
| `upload_status` | Flutter আপলোড শুরু করলে `pending`, শেষ হলে `uploaded`, সমস্যা হলে `failed` |

**আপলোড ফ্লো:**
```
Flutter → POST /api/upload (multipart) → Go
Go → ফাইল disk-এ সেভ করে → message_attachments INSERT (upload_status='uploaded')
   → messages INSERT (message_type='image') → WebSocket broadcast
```

---

### ৪.১১ `price_offers` — দরকষাকষি + Fiverr-স্টাইল অফার

এই টেবিলটা দুটো কাজ করে — সাধারণ দরকষাকষি (কাস্টমার দাম প্রস্তাব করে) এবং মার্চেন্টের Fiverr-স্টাইল custom offer পাঠানো।

| কলাম | কাজ |
|---|---|
| `product_id` | chat_rooms-এ product_id NULL থাকলেও এখানে পরে যোগ করা যাবে (merchant_profile থেকে শুরু হওয়া চ্যাটে) |
| `title` | **v2-তে নতুন।** অফারের ছোট শিরোনাম, যেমন "Custom order — ২ পিস" |
| `description` | **v2-তে নতুন।** মার্চেন্ট বিস্তারিত লিখবে — এটাই Flutter-এ Accepting Dialogue popup-এ দেখাবে |
| `offered_price` | প্রস্তাবিত দাম (০-এর বেশি হতে হবে — CHECK constraint আছে) |
| `previous_offer_id` | আগের অফারের ID — এভাবে counter-offer chain তৈরি হয় |
| `status` | `pending` → `accepted` / `rejected` / `countered` / `expired` |
| `expires_at` | অফারের মেয়াদ — ২৪ ঘণ্টার মধ্যে রেসপন্স না হলে Go cron job `expired` করে দেবে |

---

### ৪.১২ `daily_chat_usage` — দিনের কাউন্টার

**কেন দরকার?** প্রতিটা মেসেজ পাঠানোর সময় যদি `SELECT COUNT(*) FROM messages WHERE sender_id=? AND DATE(created_at)=CURDATE()` চালানো হয়, তাহলে লক্ষাধিক মেসেজ থাকলে ডাটাবেজ স্লো হবে। এই টেবিলে একটা কাউন্টার রো রাখলে একটা সহজ SELECT দিয়েই লিমিট চেক হয়।

**কীভাবে আপডেট করবেন:**
```sql
INSERT INTO daily_chat_usage (user_id, entity_id, usage_date, message_count)
VALUES (?, ?, CURDATE(), 1)
ON DUPLICATE KEY UPDATE message_count = message_count + 1;
```
ছবির জন্য একই কাজ `image_count` দিয়ে।

**UNIQUE KEY** `(user_id, entity_id, usage_date)` মানে — প্রতিটা ইউজারের প্রতিটা entity-তে প্রতিদিনের জন্য মাত্র একটা রো থাকবে।

---

### ৪.১৩ `bad_keywords` — খারাপ শব্দের লিস্ট

| কলাম | কাজ |
|---|---|
| `entity_id` | NULL = সব entity-তে; নির্দিষ্ট ID = শুধু সেই entity-তে |
| `language` | `bn` / `en` / `all` — বাংলা আর ইংরেজি দুই ভাষায় আলাদা শব্দ রাখা যাবে |
| `severity` | `block` = মেসেজ পাঠানো হবে না; `mask` = শব্দটা `***` হয়ে যাবে কিন্তু মেসেজ যাবে; `warn` = মেসেজ যাবে কিন্তু অ্যাডমিনকে জানানো হবে |

এই টেবিলে actual শব্দগুলো কোডে hardcode করা হয়নি — **অ্যাডমিন প্যানেল থেকে যোগ করুন।**

---

### ৪.১৪ `moderation_logs` — ব্লক হওয়া মেসেজের প্রমাণ

মেসেজ ব্লক বা মাস্ক হলে `messages.content`-এ আসল কথা থাকে না। কিন্তু অ্যাডমিনকে দেখতে হতে পারে কে কী লিখেছিল। এই টেবিলে সেটা সংরক্ষিত থাকে।

| কলাম | কাজ |
|---|---|
| `original_content` | আসল, আনসেন্সর লেখা — শুধু অ্যাডমিন প্যানেল দেখবে, কখনো Flutter-এ পাঠাবেন না |
| `matched_keyword_id` | কোন keyword-এ ধরা পড়েছিল |
| `reviewed_by` | কোনো অ্যাডমিন ম্যানুয়ালি রিভিউ করলে এখানে রেকর্ড থাকবে |

---

### ৪.১৫ `user_blocks` — ব্লক করার সিস্টেম

Room-এর সাথে বাঁধা না। একজন কাস্টমার একজন মার্চেন্টকে ব্লক করলে পুরো entity-তেই কার্যকর হয়।

**মেসেজ পাঠানোর আগে Go ব্যাকএন্ডে এই চেক করুন:**
```sql
SELECT id FROM user_blocks
WHERE entity_id = ?
  AND (
    (blocker_id = ? AND blocked_id = ?)
    OR
    (blocker_id = ? AND blocked_id = ?)
  )
LIMIT 1;
```
রেজাল্ট এলে মেসেজ পাঠানো আটকে দিন।

---

### ৪.১৬ `chat_reports` — অভিযোগ

কাস্টমার বা মার্চেন্ট কেউ খারাপ আচরণ পেলে report করতে পারবে।

| status | মানে |
|---|---|
| `pending` | নতুন অভিযোগ, রিভিউ হয়নি |
| `reviewing` | অ্যাডমিন দেখছে |
| `resolved` | সমাধান হয়েছে |
| `dismissed` | ভিত্তিহীন অভিযোগ, বাতিল |

---

### ৪.১৭ `contact_share_requests` — নাম্বার শেয়ারের সেফ ফ্লো

ডিফল্টভাবে কেউ কারো নাম্বার পাবে না — প্ল্যাটফর্মের বাইরে ডিল এড়াতে। কিন্তু Premium প্ল্যানে একটা অনুমতি-ভিত্তিক ফ্লো আছে:

```
কাস্টমার "নাম্বার চাই" রিকোয়েস্ট পাঠায় (status = 'pending')
  → মার্চেন্টের অ্যাপে পপআপ দেখায়: "নাম্বার দেবেন?"
  → মার্চেন্ট "হ্যাঁ" → status = 'approved', shared_phone আর shared_at ভরে যায়
  → Flutter কাস্টমার-কে নাম্বার দেখায়
  → মার্চেন্ট "না" → status = 'rejected'
  → ২৪ ঘণ্টায় সাড়া না দিলে → status = 'expired' (cron job)
```

---

### ৪.১৮ `user_devices` — পুশ নোটিফিকেশন টোকেন

ইউজার অফলাইনে থাকলেও যাতে notification যায়। WebSocket connected থাকলে এই টেবিল লাগে না — সরাসরি WebSocket দিয়ে পাঠানো যায়।

| কলাম | কাজ |
|---|---|
| `push_token` | UNIQUE — একই token দুবার থাকতে পারবে না |
| `platform` | `android` / `ios` / `web` |
| `is_active` | ইউজার logout করলে FALSE করুন |

---

<a id="flows"></a>
## ৫. বিজনেস ফ্লো — বাস্তব ঘটনার মতো করে

### ফ্লো ১ — প্রোডাক্ট পেজ থেকে চ্যাট

```
রাহেলা PaiMart অ্যাপে একটা ফ্যানের দাম ৩৫০০ টাকা দেখল
→ products.is_negotiable = TRUE বলে "দাম কমাতে কথা বলুন" বাটন দেখাচ্ছে
→ রাহেলা বাটনে চাপল

Go ব্যাকএন্ড চেক করে:
  ১. এই customer + merchant + product_id-এর কোনো active রুম কি আগে থেকে আছে?
     → আছে: সেই রুমেই নিয়ে যাও
     → নেই: নতুন chat_rooms রো INSERT করো
         (entity_id, customer_id, merchant_id, product_id,
          product_name_snapshot='সিলিং ফ্যান ৫৬"',
          initiation_source='product_page')

Flutter WebSocket-এ সেই room-এ join করে
মার্চেন্টের অ্যাপে নতুন চ্যাট notification আসে
```

### ফ্লো ২ — মার্চেন্ট প্রোফাইল থেকে চ্যাট

```
করিম PaiBazar-এ "রাজু ইলেকট্রনিক্স"-এর প্রোফাইল দেখছে
→ "মেসেজ করুন" বাটনে চাপল

Go ব্যাকএন্ড chat_rooms তৈরি করে:
  (initiation_source='merchant_profile', product_id=NULL)

করিম লেখল: "আপনার কাছে কি ওয়াশিং মেশিন আছে?"
→ messages INSERT, message_type='text'
→ chat_rooms.last_message_at আপডেট
→ WebSocket দিয়ে মার্চেন্টকে জানানো হলো

মার্চেন্ট "হ্যাঁ আছে, ১৫০০০ টাকা" বলল
→ করিম চাইলে এখন price_offer পাঠাতে পারবে — product_id সেখানে বসাবে
```

### ফ্লো ৩ — মেসেজ পাঠানোর সময় Go ব্যাকএন্ডের চেকলিস্ট

```
কাস্টমার মেসেজ পাঠাতে চাইছে:

১. user_blocks চেক → ব্লক থাকলে: "এই মার্চেন্টের সাথে কথা বলতে পারবেন না" error
২. user_subscriptions + subscription_plans চেক → active plan বের করো
③. daily_chat_usage চেক → আজকের message_count >= plan.max_messages_per_day?
   → হ্যাঁ: "আজকের মেসেজ লিমিট শেষ, প্ল্যান আপগ্রেড করুন" error
④. message_type = 'image' হলে:
   → entity_chat_settings.allow_image_attachment_override চেক
   → plan.can_send_images চেক
   → daily_chat_usage.image_count >= plan.max_images_per_day? → error
⑤. content-এ bad_keywords চেক:
   → severity='block': messages INSERT (content = placeholder), moderation_logs INSERT, WebSocket দিয়ে শুধু sender-কে error জানাও
   → severity='mask': শব্দ *** করো, messages INSERT, moderation_logs INSERT
   → severity='warn': messages INSERT, moderation_logs INSERT (admin queue-এ যাবে)
⑥. messages INSERT (status='sent')
⑦. daily_chat_usage UPDATE (ON DUPLICATE KEY)
⑧. chat_rooms.last_message_* UPDATE
⑨. WebSocket দিয়ে recipient-কে broadcast
   → অনলাইন না থাকলে user_devices দিয়ে push notification
```

---

<a id="fiverr-flow"></a>
## ৬. Fiverr-স্টাইল Accepting Dialogue কীভাবে কাজ করে

Fiverr-এ seller যেভাবে custom offer পাঠায়, ঠিক সেইভাবে মার্চেন্ট ড্যাশবোর্ড থেকে।

```
মার্চেন্ট ড্যাশবোর্ড → চ্যাট স্ক্রিন → "Custom Offer পাঠান" বাটন

মার্চেন্ট form fill করে:
  - title: "সিলিং ফ্যান ৫৬" — বিশেষ ছাড়"
  - description: "আপনার জন্য ৩২০০ টাকায় দেব। delivery ২ দিনে। warranty ১ বছর।"
  - offered_price: 3200
  - expires_at: এখন থেকে ২৪ ঘণ্টা পরে

Go ব্যাকএন্ড:
  → messages INSERT (message_type = 'price_offer', sender = merchant)
  → price_offers INSERT (status='pending', title=..., description=..., offered_price=3200)
  → WebSocket দিয়ে customer-কে পাঠানো হলো

Customer-এর Flutter অ্যাপ:
  → message_type = 'price_offer' দেখে বিশেষ "অফার কার্ড" UI render করে
  → কার্ডে [Accept] আর [Decline] বাটন
  → Accept চাপলে → price_offers.status = 'accepted', responded_at = NOW()
  → Decline চাপলে → price_offers.status = 'rejected'
  → কাউন্টার অফার দিলে → পুরোনো offer.status = 'countered',
     নতুন price_offers রো (previous_offer_id = পুরোনোটার id, offered_by = customer)
```

---

<a id="subscription-logic"></a>
## ৭. সাবস্ক্রিপশন লজিক — একটু সহজ করে

```
কোনো কাজ করার আগে Go এই ক্রমে চেক করে:

entity_chat_settings  →  subscription_plans  →  daily_chat_usage

উদাহরণ — "কাস্টমার ছবি পাঠাতে পারবে?"

১. entity_chat_settings.allow_image_attachment_override
   → NULL: পরের ধাপে যাও
   → FALSE: ❌ বন্ধ (কারণ যাই হোক)
   → TRUE: ✅ খোলা (কারণ যাই হোক)

২. subscription_plans.can_send_images
   → FALSE: ❌ এই প্ল্যানে ছবি নেই

৩. daily_chat_usage.image_count >= subscription_plans.max_images_per_day
   → হ্যাঁ: ❌ আজকের কোটা শেষ

সব ঠিক থাকলে ✅ ছবি পাঠাতে দাও
```

---

<a id="moderation"></a>
## ৮. মডারেশন — বাজে শব্দ কীভাবে ব্লক হয়

```
মেসেজ আসল → Go middleware content স্ক্যান করে:

bad_keywords থেকে active keywords লোড করো
(entity_id = current entity OR entity_id IS NULL)

প্রতিটা keyword-এর বিরুদ্ধে content match করো (case-insensitive):

  severity = 'block':
    → messages.content = "[এই বার্তাটি সরানো হয়েছে]"
    → messages.moderation_status = 'blocked'
    → moderation_logs INSERT (original_content = আসল লেখা)
    → শুধু sender-কে error জানাও, recipient কিছু পাবে না

  severity = 'mask':
    → bad word গুলো *** দিয়ে replace করো
    → messages.content = masked content
    → messages.moderation_status = 'clean' (কারণ মেসেজ যাচ্ছে)
    → moderation_logs INSERT

  severity = 'warn':
    → messages.content = আসল content (কিছু বদলাবে না)
    → messages.moderation_status = 'flagged'
    → moderation_logs INSERT (admin queue-এ জমা হবে)
```

⚡ **পারফরম্যান্স টিপস:** প্রতি মেসেজে DB query না করে Go startup-এ keywords একবার লোড করে in-memory cache রাখুন। প্রতি ৫ মিনিটে বা admin আপডেটের পর refresh করুন।

---

<a id="performance"></a>
## ৯. ইনডেক্স ও পারফরম্যান্স নোট

| ইনডেক্স | টেবিল | কেন গুরুত্বপূর্ণ |
|---|---|---|
| `idx_messages_room_created` | messages | চ্যাট স্ক্রিনের pagination — সবচেয়ে বেশি ব্যবহৃত query |
| `idx_rooms_customer` | chat_rooms | কাস্টমারের চ্যাট লিস্ট লোড |
| `idx_rooms_merchant` | chat_rooms | মার্চেন্ট ড্যাশবোর্ডের চ্যাট লিস্ট লোড |
| `uq_usage_user_entity_date` | daily_chat_usage | ON DUPLICATE KEY UPDATE দ্রুত কাজ করার জন্য |
| `idx_products_negotiable` | products | প্রোডাক্ট লিস্টে শুধু negotiable প্রোডাক্ট ফিল্টার করতে |

**ভবিষ্যতে স্কেল বাড়লে:**
`messages` টেবিল মাসভিত্তিক partition করা যাবে (`created_at` দিয়ে)। কিন্তু InnoDB-তে partitioned টেবিলে FOREIGN KEY কাজ করে না — তখন FK সরিয়ে অ্যাপ লেয়ারে integrity মেইনটেইন করতে হবে। লঞ্চের সময় এটা নিয়ে ভাবার দরকার নেই।

---

<a id="next-steps"></a>
## ১০. Go ব্যাকএন্ডে পরবর্তী কাজের ক্রম

এই schema production-ready। এখন Go ব্যাকএন্ডের কাজ এই ক্রমে করুন:

```
Step 1: golang-migrate দিয়ে এই SQL-কে migration ফাইলে ভাঙুন
        (001_entities.up.sql, 002_users.up.sql...)

Step 2: WebSocket Hub — gorilla/websocket বা nhooyr.io/websocket দিয়ে
        room-based connection manager লিখুন
        (কোন user কোন room-এ connected সেটা in-memory map-এ রাখুন)

Step 3: Chat REST API
        POST   /api/rooms               → chat_rooms তৈরি বা return
        GET    /api/rooms/:id/messages  → pagination সহ history
        POST   /api/upload              → ছবি আপলোড → message_attachments

Step 4: WebSocket Message Handler
        send_message → checklist (block, limit, keyword) → DB insert → broadcast

Step 5: Price Offer API
        POST /api/rooms/:id/offers      → price_offers INSERT
        PUT  /api/offers/:id/respond    → accept / reject / counter

Step 6: Cron Jobs (প্রতিদিন রাত ১২টায়)
        → expired price_offers আপডেট
        → auto_close_after_days পার হয়ে যাওয়া rooms বন্ধ
        → expired contact_share_requests আপডেট
```

---

> এই ডকুমেন্ট v2 schema (`pai_entity_chat.sql`)-এর সাথে সম্পূর্ণ সিঙ্ক করা। স্কিমা পরিবর্তন হলে এই ডকুমেন্টও আপডেট করুন।
