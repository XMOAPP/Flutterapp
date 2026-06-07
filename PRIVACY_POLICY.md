# XMO Privacy Policy

Effective date: June 5, 2026

This Privacy Policy explains how XMO collects, uses, stores, shares, and protects information when you use the XMO mobile app, web app, Matrix homeserver, authentication services, calling features, story features, wallet login, and donation features.

XMO is a Matrix-based messaging application. Some parts of the service are provided by XMO-operated infrastructure, such as the XMO Matrix homeserver and OTP backend. Some parts rely on third-party services, such as Matrix protocol infrastructure, email delivery, wallet providers, WalletConnect/Reown, Thirdweb, Firebase initialization services, and blockchain networks.

If you do not agree with this Privacy Policy, do not use XMO.

This policy is written to describe how XMO works from a privacy perspective. It does not replace any terms of service, community rules, blockchain wallet rules, Matrix homeserver rules, or third-party provider policies that may also apply to your use of the app.

## Summary

XMO is designed as a private messaging and calling app built on Matrix, with a long-term direction toward end-to-end encrypted communication, decentralized ownership, and stronger user control over data. Your account, rooms, messages, media, groups, channels, and stories are processed through Matrix-compatible infrastructure. When you send something to another person or room, that content has to be delivered to the relevant recipients and may be stored on the homeserver so those recipients can access it.

XMO also stores some information locally on your device to make the app work smoothly. This includes login/session state, settings, cached media previews, downloaded files, local call history, and temporary upload state. Local information helps the app show chats faster, remember your choices, and support features such as storage usage, shared media, pending uploads, and call history.

Some features use separate services. Email verification uses an OTP backend. Wallet login uses wallet connection and message signing. Donations use Thirdweb checkout and public blockchain networks. These services process the information needed for their specific feature.

Our future privacy direction is to make XMO more secure by reducing unnecessary data collection, keeping sensitive credentials out of the mobile app, improving encrypted messaging support, strengthening account and session protection, and using decentralized or federated architecture where it gives users more control and resilience. We will continue to describe important privacy limits clearly, because even secure systems may still process metadata, local cache, recipient copies, server routing information, or blockchain transaction records.

## Who This Policy Applies To

This policy applies to people who install, access, register for, log in to, or otherwise use XMO. It also applies when you interact with an XMO user, group, channel, story, call, invite link, shared media item, wallet login flow, or donation checkout flow.

If you use XMO through a Matrix account hosted on a different homeserver, that homeserver may have its own privacy policy. If federation is enabled, your information may be processed by both XMO-operated services and other Matrix servers involved in the rooms you join.

## XMO Architecture From a Privacy Perspective

XMO has several major privacy-relevant parts. The Flutter app runs on your device and provides the user interface for chats, calls, media, stories, settings, wallet login, and donations. The Matrix homeserver stores and synchronizes account data, rooms, messages, media, profiles, group/channel state, read receipts, and other Matrix events. The OTP backend sends and verifies email codes during registration or verification flows. Wallet login uses wallet connection infrastructure and a wallet signature to prove wallet ownership. Donations use the XMO donation backend and Thirdweb to create a checkout link.

This means not every piece of data is handled in the same place. Chat messages and media are Matrix data. OTP codes are temporary backend data. Downloaded files and cache are local device data. Wallet addresses and blockchain transactions are wallet/blockchain data. Understanding this separation is important because deleting or changing one type of data may not automatically delete or change all other related copies.

XMO's architecture is intended to avoid a fully centralized model where one app server controls every user interaction. Matrix allows homeservers to interoperate, which can support a more decentralized communication model when federation is enabled. In that model, users may communicate across different homeservers instead of depending only on one central service. Decentralization can improve portability and resilience, but it also means that data may be processed by more than one server, and each independent server may apply its own retention, moderation, and security practices.

## 1. Information We Collect

### 1.1 Account Information

When you create or use an XMO account, we may collect:

Your username and Matrix user ID identify your account across XMO and the Matrix homeserver. Your display name and profile photo or avatar help other users recognize you in direct chats, groups, channels, stories, search results, and call screens. If you register with email verification, XMO processes the email address you provide so that an OTP code can be sent and verified. If you provide a phone number, XMO processes the number and selected country code for registration-related account information.

If you use username and password login, your credentials are handled through the Matrix authentication flow. If you use wallet login, XMO processes your wallet address and the signed authentication message needed to prove that you control that wallet. XMO also stores or processes profile settings, privacy settings, account visibility preferences, and related account configuration so the app can apply your choices consistently.

Your account information may be visible to other users depending on how you use the app and how your privacy settings are configured. For example, your display name and profile photo may appear in direct chats, groups, channels, stories, call screens, member lists, search results, and invite-related screens. If you remove your profile photo, XMO may show a fallback avatar instead.

### 1.2 Messages, Rooms, Groups, Channels, and Stories

XMO processes the content and metadata required to provide messaging features. This includes direct messages, group messages, channel posts, saved messages, replies, reactions, edits, pinned messages, deleted or redacted messages, and forwarded messages. When you send or receive media, XMO processes the related photos, videos, audio files, voice messages, documents, APKs, PDFs, links, thumbnails, captions, filenames, file sizes, MIME types, and upload or download metadata needed to show, send, receive, preview, open, and organize those items.

For stories, XMO processes story text, story media, captions, timestamps, selected privacy audience, view counts, and story viewer information. For groups and channels, XMO processes names, descriptions, avatars, members, subscribers, admins, roles, permissions, invite links, pinned messages, and moderation-related actions. Matrix room identifiers, event identifiers, room state events, read receipts, delivery status, typing or online indicators where supported, and message timestamps are also processed so XMO can keep conversations synchronized and show the correct chat state.

Message and media metadata can be privacy-relevant even when it is not the message body itself. For example, timestamps can show when you were active, file names can reveal information about a document, read receipts can show when a message was read, and group membership state can show which users are part of a room. XMO processes this information because it is needed for the Matrix protocol and for app features such as chat lists, shared media, search, call banners, pinned messages, delivery ticks, and unread badges.

Links sent in chats may be detected so the app can make them clickable and show them in shared media link tabs. Opening a link may send information to the destination website or app, such as your IP address, browser/app information, and the URL you opened. XMO does not control the privacy practices of websites you open from messages.

### 1.3 Calls

When you use voice or video calling, XMO processes information needed to place, receive, join, leave, reject, and end calls. This includes the caller, recipient, group, channel or room identifiers associated with the call, the call type, current call state, timestamps, duration, whether a call was missed, rejected, answered, ended, or left, and local call history used to show recent call activity.

XMO also processes audio and video device state so call controls work correctly. For example, the app needs to know whether your microphone is muted, whether your camera is enabled, whether audio is routed through the earpiece or speaker, whether the ringtone is active, and whether the call is minimized into picture-in-picture style UI. WebRTC signaling and media connection information are processed only as needed to establish and maintain calls.

XMO does not intentionally record your voice or video calls. Calls may still involve device permissions, WebRTC routing, and server-side signaling metadata needed to operate the call.

Incoming call notifications, fullscreen call screens, call banners, join/rejoin prompts, ringtone behavior, accept/decline actions, and call history entries are part of the call experience. These features may process who called, which room the call belongs to, whether the call was voice or video, and whether you answered, declined, missed, joined, left, or ended the call.

### 1.4 Device, App, and Usage Information

XMO may process technical information about your device and app environment, such as device type, operating system, app version, platform information, IP address, and network request metadata when you connect to XMO services. This information is needed to deliver app features, maintain sessions, communicate with the Matrix homeserver, upload and download media, and troubleshoot service issues.

The app also processes local settings and app state, including notification preferences, media auto-download preferences, privacy preferences, story visibility settings, blocked users, local cache data, downloaded media records, shared media indexes, and storage usage information. Error messages generated by the app or backend may be processed so that failed features can be debugged and improved.

XMO may generate local previews or thumbnails for photos, videos, files, audio, and shared media so that content can be displayed efficiently. These previews may be cached on your device. Storage usage screens may scan local downloads and cached media to show how much space is being used by photos, videos, audio, files, and cached previews.

### 1.5 Wallet and Donation Information

If you use wallet login or crypto donations, XMO processes your wallet address and the wallet signature used to authenticate your account. The signature is used to prove control of the wallet address; it does not give XMO access to your private key.

If you donate through the crypto donation feature, XMO processes the donation amount you enter and the checkout link information returned by Thirdweb. The resulting blockchain transaction information may be public on the relevant blockchain, including wallet addresses, transaction identifiers, token information, network information, and transaction amounts.

XMO does not ask for or store your wallet private key or seed phrase. Never share your wallet private key or seed phrase with anyone.

Wallet signatures should be treated carefully. A signature proves that a wallet approved a specific message. XMO uses signatures only for authentication-related purposes in the wallet login flow. You should always review wallet prompts before signing and make sure the prompt is for XMO and not for an unknown website or malicious app.

### 1.6 Information From Permissions

XMO may request camera access so you can take photos or videos, update profile images, create stories, and participate in video calls. Microphone access is used for voice messages, audio recording, and voice or video calls. File and gallery access is used when you choose media or documents to send, open, download, share, or save.

The app may also need audio-setting access to route call audio, speaker mode, earpiece mode, and ringtone behavior correctly. Internet and network access are required to connect to Matrix, media, authentication, donation, wallet, link preview, and other app services.

Permission requests are controlled by your device operating system. You can usually revoke permissions in your device settings, but some XMO features may stop working or work only partially if the required permission is disabled. For example, video calls require camera access, voice messages require microphone access, and sending gallery media requires file or gallery access.

### 1.7 Information Other Users Provide About You

Other users may provide information about you when they interact with XMO. For example, they may send you messages, add you to groups, invite you to channels, mention you, forward your messages, react to your content, view your stories, call you, or save messages involving you. XMO processes those interactions as part of normal app functionality.

Other users may also upload content that includes your image, voice, name, username, wallet address, phone number, or other personal information. XMO cannot control what other users choose to share, but we may respond to abuse reports or lawful requests where required.

XMO uses these permissions only to provide the feature you choose to use.

## 2. How We Use Information

We use information to create, verify, authenticate, and manage XMO accounts. This includes processing usernames, passwords, email OTP verification, phone number information where provided, wallet authentication signatures, profile settings, and account preferences.

We use message, media, room, story, and call information to provide the core XMO experience. This includes direct chats, groups, channels, saved messages, story creation and viewing, voice and video calls, search, shared media tabs, file handling, link handling, notifications, pinned messages, badges, timestamps, delivery status, read receipts, call banners, call screens, and local call history.

We use media and file information to upload, download, preview, cache, display, organize, and open photos, videos, audio, voice messages, documents, links, and other attachments. We use privacy and permission-related information to apply blocked-user settings, profile visibility, story visibility, account visibility, group permissions, channel permissions, and other user choices.

We may also use information to improve reliability, debug errors, prevent spam or abuse, maintain service security, comply with legal obligations, respond to lawful requests, and enforce our rights.

## 2.1 Legal Bases Where Applicable

Depending on where you live, privacy law may require us to explain the legal basis for processing personal information. XMO may process information because it is necessary to provide the app and services you requested, such as creating an account, sending messages, joining rooms, displaying media, or placing calls. We may process information with your consent, such as when you grant camera, microphone, gallery, or wallet permissions. We may process information based on legitimate interests, such as maintaining security, preventing abuse, debugging service errors, and improving reliability. We may also process information when required to comply with legal obligations.

Where consent is required, you may withdraw consent through app settings, device settings, or by stopping use of the relevant feature. Withdrawing consent may prevent certain features from working.

## 3. How Messages and Media Are Stored

XMO uses the Matrix protocol. Messages, media, room state, profile information, group/channel state, stories, and related metadata may be stored on the Matrix homeserver that hosts your account or the room.

For XMO-operated accounts, the default homeserver is:

`xmo-matrix.centralindia.cloudapp.azure.com`

Matrix rooms may involve more than one server if federation is enabled or if users from other homeservers participate. In that case, data may also be processed by other Matrix servers according to their own policies.

XMO also stores some data locally on your device. This may include login or session data that keeps you signed in, app settings, privacy settings, cached media previews, downloaded files, local call history, local shared-media or storage indexes, and temporary UI state needed for pending uploads, upload progress, and app behavior. Local storage helps the app load faster, show downloaded media, remember your settings, and continue common workflows without repeatedly requesting the same information from the server.

Deleting local cache or downloaded files removes them from your device storage, but it does not necessarily delete copies already stored on the Matrix homeserver, recipient devices, other federated servers, blockchain networks, or third-party services.

### 3.1 Matrix Federation

Matrix can support federation, which means rooms may include users from different homeservers. If federation is active and a room includes users from another homeserver, room events may be shared with that homeserver so its users can participate. Those servers may store and process room data according to their own policies and configurations. XMO cannot control independent Matrix servers that are not operated by XMO.

### 3.2 End-to-End Encryption

XMO is being built with an end-to-end encrypted future in mind. End-to-end encryption is important because it is designed so that message contents are protected between the sending and receiving devices, rather than being readable as plain text by infrastructure that only delivers the message. Where Matrix end-to-end encryption is enabled and correctly configured, message content may be protected from server-side access in that way.

Some Matrix rooms may support end-to-end encryption depending on server configuration, client configuration, room settings, and user setup. This policy does not promise that every XMO message, media item, call, story, group, or channel is end-to-end encrypted today. You should treat encryption status as a room-specific and feature-specific property. Even where encryption is available, metadata such as room membership, timestamps, server routing information, file sizes, device information, and some state events may still be processed to provide the service.

Our goal is to move XMO toward stronger encrypted communication over time. That may include improving encrypted chat behavior, encrypted media handling, secure key management, device verification, recovery behavior, and clearer encryption indicators in the user interface. Until those protections are fully implemented and enabled for the relevant feature, you should not assume that every interaction is end-to-end encrypted.

### 3.3 Local Downloads and Cache

When you download files or media, those items may be stored in app-specific folders or device-accessible storage depending on platform behavior. Downloaded files may remain on your device after you close XMO. Cached previews may also remain until you clear cache, uninstall the app, or the operating system removes cached data. If you share, open, or export downloaded files into another app, that other app may process the file under its own policy.

## 4. Message Deletion and Redaction

When you delete or redact a message, XMO requests a Matrix redaction for that event. Redaction removes or hides the message content where the redaction is accepted and synchronized.

However, deletion does not guarantee that every copy disappears everywhere. Other users may have already seen, copied, screenshotted, downloaded, or forwarded the content. Other Matrix clients, servers, federated servers, or cached timelines may temporarily retain older event data. Files that recipients downloaded to their own devices are outside XMO's control. Blockchain donation records cannot be deleted from public blockchains.

If you delete a group or channel, the effect depends on your role, Matrix room state, and whether other users or servers still have access to room history. If you leave a room, your local app may stop showing it, but prior room events may still exist for other members or on servers where they were already synchronized.

## 5. Shared Media, Files, Links, and Search

XMO may index loaded room events to show shared media tabs, file lists, links, downloaded media, and storage usage. These indexes are used to make content easier to find inside the app.

Older media may appear after the app loads older Matrix history from the server. Shared media visibility depends on what room history is available to your account and what the app has loaded or indexed.

Shared media tabs may group content by type, such as photos, videos, audio, files, and links. File previews may use filenames, MIME types, file extensions, thumbnails, icons, sizes, and timestamps to display useful information. Link tabs may show URLs extracted from text messages. These features are designed for convenience and do not change who can access the underlying room history.

## 6. Calls and Call History

XMO supports direct and group voice/video calling. Call signaling and call state are processed through Matrix and WebRTC-related services. XMO may store local call history on your device, scoped to the current logged-in user, including call participants, room, call type, direction, status, timestamp, and duration.

Group call creators may have permission to end a group call for everyone, while other participants may only leave the call for themselves. Incoming call screens, banners, ringtones, accept/decline actions, and join/rejoin banners are processed to provide call functionality.

Direct calls and group calls may behave differently because they involve different Matrix/WebRTC call flows. A direct call is generally between two users. A group call involves a room and may include several participants. XMO processes the minimum call state needed to show the correct UI, route audio, manage camera and microphone state, and update local call history.

## 7. Email OTP Verification

XMO uses an OTP backend to send verification codes by email. When you request verification, the backend receives the email address you submit, generates a six-digit OTP, stores that OTP temporarily in memory, limits verification attempts, and sends the OTP using configured email delivery credentials. The purpose of this processing is to verify that you control the email address before completing the relevant registration or verification flow.

OTP records are temporary and are removed after expiry, successful verification, or excessive failed attempts.

The OTP backend is not intended to permanently store your OTP code. Because email delivery depends on external email infrastructure, the email provider and receiving email service may also process the verification email according to their own policies.

## 8. Wallet Login

If you choose wallet login, you enter or choose a username and connect a wallet. XMO asks your wallet to sign an authentication message. The signed message proves that you control the wallet address and allows XMO to register or authenticate your Matrix account for the selected username. This signature process does not require a blockchain transaction for login and does not give XMO access to your wallet private key.

Signing in with a wallet does not require a blockchain transaction for authentication. Wallet login does not give XMO your private key.

If you create an account with wallet login, the username may be checked for availability before registration. If the username is already taken, XMO may show an error and ask you to choose another username. If you log in with an existing wallet-linked account, XMO uses the wallet signature and account information to authenticate you.

## 9. Donations

If you use the donation feature, XMO sends donation amount information to the XMO donation backend, which creates a checkout link through Thirdweb. Thirdweb, wallet providers, blockchain networks, payment routers, and other crypto infrastructure may process additional information according to their own privacy policies.

Blockchain transactions are public and may reveal wallet addresses, amounts, token types, network information, and transaction history.

Donation checkout links may open inside a webview or in an external browser depending on the app configuration. Once you interact with a checkout page, Thirdweb, wallet providers, payment routers, blockchain networks, and any selected wallet app may receive information needed to process the donation. XMO does not control blockchain confirmation times, gas fees, failed wallet transactions, or third-party checkout availability.

## 10. Third-Party Services

XMO may rely on or interact with several third-party services and infrastructure providers. Matrix/Synapse homeserver services are used for account, room, message, media, and state synchronization. Email delivery services are used to send OTP verification codes. Firebase initialization services may be used as part of the app platform setup.

Wallet providers such as MetaMask, Coinbase Wallet, Rainbow, or other WalletConnect-compatible wallets may be used when you choose wallet login. WalletConnect/Reown wallet connection infrastructure may help connect the app to wallet software. Thirdweb is used to create donation checkout links. Blockchain networks process public blockchain transactions related to crypto donations. If you open a URL from a message, the destination website or app may receive information according to its own privacy policy. Your device operating system also processes camera, microphone, file, storage, notification, and audio-routing permissions.

Third-party services are independent from XMO. Their privacy practices, security practices, data retention, international transfers, user rights processes, and support channels may differ from ours. You should review their policies before using features that rely on them.

Third-party services may collect and process information under their own privacy policies. XMO is not responsible for the privacy practices of third-party websites, wallets, networks, or services.

## 11. How We Share Information

We share or disclose information when necessary to operate XMO. For example, message content, media, room state, profile data, call signaling, and account data may be shared through Matrix infrastructure so that recipients, group members, channel subscribers, and authorized story viewers can receive and view the content. The information shown to other users depends on the feature you use and the privacy settings you select.

We may share email addresses with the email delivery systems needed to send OTP codes. Wallet login and donation information may be shared with wallet providers, WalletConnect/Reown infrastructure, Thirdweb, and blockchain networks as needed to complete those flows. We may also disclose information to comply with law, respond to legal process, enforce our rights, maintain service security, or protect XMO, users, and the public from spam, abuse, fraud, or harm.

We do not sell your personal information.

We do not share your private wallet keys because XMO never receives them. We do not intentionally sell message contents, contact lists, wallet signatures, or call contents. However, messages and media are shared with the users and rooms you choose, and blockchain transactions are public by design.

## 12. Privacy Controls

XMO includes privacy and account controls that may allow you to change your profile name and profile photo, remove your profile photo, configure account visibility, choose who can see your profile picture, choose who can view stories, block users, mute chats, delete messages where supported, and manage group or channel actions depending on your role.

The app also includes local controls for clearing media cache, managing downloaded storage, and logging out of your account. Some controls affect only your local device, such as clearing downloaded files. Other controls update Matrix account data, Matrix room state, group or channel state, or story visibility settings on the server.

Privacy controls may not be retroactive in every situation. For example, changing story visibility affects future or currently available story access according to app behavior, but it cannot remove screenshots already taken by other users. Blocking a user may stop or limit interactions in XMO, but it may not remove content already sent in shared rooms. Clearing cache removes local cached data, but it does not delete server-side room history.

Some controls affect only your local device. Others send Matrix state or account updates to the server.

## 13. Security

We use reasonable technical and organizational measures to protect XMO services. XMO uses Matrix authentication/session handling and local app storage for account/session data. Sensitive backend secrets, such as email credentials and Thirdweb secret keys, should be stored only on server infrastructure and never inside the public mobile app.

XMO's security direction is to make the app more secure over time by reducing unnecessary data exposure, improving end-to-end encryption support, separating backend secrets from client code, protecting session data, limiting sensitive local storage where practical, and improving how the app handles account recovery, device trust, call state, media uploads, and cached content. Security work is an ongoing process, not a one-time feature.

Decentralized and federated systems can improve resilience, but they also require clear security boundaries. XMO-operated infrastructure can be managed according to XMO security practices, while independent homeservers, wallet providers, blockchain services, and other third-party systems are controlled by their own operators. Where XMO interacts with those systems, we aim to share only what is needed for the relevant feature.

No service can guarantee absolute security. You are responsible for keeping your password, device, wallet, and recovery information secure.

You should use a strong password, keep your device updated, protect your wallet, avoid signing unknown wallet prompts, avoid sharing OTP codes, and be careful when opening links or files from other users. If you believe your account, email, wallet, or device has been compromised, you should take immediate steps to secure it and contact us if you need assistance with XMO-specific account issues.

## 13.1 Abuse, Safety, and Moderation

XMO may process account, room, message, call, and technical information to investigate abuse, spam, fraud, impersonation, illegal content, security threats, or violations of applicable rules. Group and channel admins may also have moderation capabilities within their rooms, such as managing members, permissions, invite links, pinned messages, or deleted content depending on their role.

## 14. Data Retention

We retain information for as long as needed to provide XMO, comply with legal obligations, resolve disputes, enforce agreements, and maintain security.

Retention depends on the type of data. Matrix messages, media, rooms, groups, channels, stories, and profile data may remain on the homeserver until they are deleted, redacted, expired, or removed according to server configuration and Matrix behavior. OTP records are temporary and expire quickly after a short verification window, successful verification, or excessive failed attempts.

Local cache and downloaded files remain on your device until you clear them, delete them, uninstall the app, or the operating system removes them. Local call history remains on your device until it is cleared or overwritten by app limits. Blockchain transaction data may remain publicly available indefinitely because public blockchains are designed to preserve transaction records.

If your account is inactive, some data may remain on the Matrix homeserver unless deleted, redacted, expired by server policy, or removed through an applicable account deletion process. If a room is shared with other users, their access to room history may continue according to Matrix behavior, room settings, and server configuration.

## 15. International Transfers

XMO services, Matrix servers, third-party providers, wallet providers, and blockchain infrastructure may process information in countries different from where you live. By using XMO, you understand that your information may be transferred, stored, and processed in those locations.

## 16. Children's Privacy

XMO is not intended for children under the minimum age required by applicable law. If we learn that a child has provided personal information without required consent, we will take reasonable steps to delete or disable the account where required.

## 17. Your Choices and Rights

Depending on your location, you may have rights to access, correct, export, delete, restrict, or object to processing of your personal information. Some data can be changed directly in the app. For server-side requests, contact us using the contact details below.

Some requests may be limited by Matrix federation, recipient copies, technical constraints, legal requirements, security needs, or blockchain immutability.

Examples of actions you can take inside XMO include changing your display name, changing or removing your profile photo, adjusting privacy settings, blocking users, deleting supported messages, clearing local cache, managing downloads, logging out, and leaving groups or channels where available. For requests that cannot be completed directly in the app, you may contact us using the contact information in this policy.

## 18. Changes to This Policy

We may update this Privacy Policy from time to time. If we make material changes, we will update the effective date and may provide notice in the app or through another appropriate method.

## 19. Contact

For privacy questions or requests, contact:

`xmoapp@proton.me`

If XMO is operated by a company or organization, add the legal entity name and registered address here before publishing this policy.

## 20. Reference Policies Reviewed

This policy was prepared after reviewing privacy-policy structures and coverage patterns from major messaging platforms, including Telegram, WhatsApp, and WeChat, and then tailoring the content to XMO's actual Matrix-based codebase and features.
