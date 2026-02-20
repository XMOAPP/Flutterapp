class ChatModel {
  final String id;
  final String name;
  final String lastMessage;
  final String time;
  final String avatarText;
  final String? avatarColor; // hex color for colored avatars
  final bool isGroup;
  final int unreadCount;
  final bool isRead;
  final bool hasDoubleCheck;
  final bool isOnline;
  final String? senderName; // for group messages
  final String? imageUrl;

  const ChatModel({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.avatarText,
    this.avatarColor,
    this.isGroup = false,
    this.unreadCount = 0,
    this.isRead = false,
    this.hasDoubleCheck = false,
    this.isOnline = false,
    this.senderName,
    this.imageUrl,
  });
}

class StoryModel {
  final String id;
  final String name;
  final String avatarText;
  final String? avatarColor;
  final String backgroundImageUrl;
  final bool isYourStory;
  final String? profileImageUrl;

  const StoryModel({
    required this.id,
    required this.name,
    required this.avatarText,
    this.avatarColor,
    required this.backgroundImageUrl,
    this.profileImageUrl,
    this.isYourStory = false,
  });
}

class MessageModel {
  final String id;
  final String content;
  final bool isOutgoing;
  final String time;
  final MessageType type;
  final String? imageUrl;
  final String? audioDuration;

  const MessageModel({
    required this.id,
    required this.content,
    required this.isOutgoing,
    required this.time,
    this.type = MessageType.text,
    this.imageUrl,
    this.audioDuration,
  });
}

enum MessageType { text, image, audio }

// Mock Data
class MockData {
  static const List<ChatModel> allChats = [
    ChatModel(
      id: '1',
      name: 'Book Club',
      lastMessage: 'Next read: The Great Gatsby',
      time: 'Wed',
      avatarText: 'BC',
      avatarColor: '#E040FB',
      isGroup: true,
      imageUrl:
          'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=400',
    ),
    ChatModel(
      id: '2',
      name: 'College Friends',
      lastMessage: 'Jake: Reunion next month?',
      time: 'Tue',
      avatarText: 'CF',
      isGroup: true,
      senderName: 'Jake',
      imageUrl:
          'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=400',
    ),
    ChatModel(
      id: '3',
      name: 'Carol White',
      imageUrl:
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
      lastMessage: 'See you at the meeting tomorrow!',
      time: 'Yesterday',
      avatarText: 'CW',
      isRead: true,
      hasDoubleCheck: true,
    ),
    ChatModel(
      id: '4',
      name: 'Bob Smith',
      imageUrl:
          'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
      lastMessage: 'Thanks for your help with the code review!',
      time: 'Yesterday',
      avatarText: 'BS',
      isRead: true,
      hasDoubleCheck: true,
    ),
    ChatModel(
      id: '5',
      name: 'Eva Green',
      imageUrl:
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
      lastMessage: 'Happy birthday!',
      time: 'Sat',
      avatarText: 'EG',
      avatarColor: '#FF8C00',
      isRead: true,
      hasDoubleCheck: false,
    ),
    ChatModel(
      id: '6',
      name: 'David Brown',
      imageUrl:
          'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=400',
      lastMessage: 'The concert was amazing!',
      time: 'Sun',
      avatarText: 'DB',
      isRead: true,
      hasDoubleCheck: false,
    ),
    ChatModel(
      id: '7',
      name: 'Team Project',
      lastMessage: 'Sarah: The presentation is ready for review',
      time: '1:15 PM',
      avatarText: 'TP',
      isGroup: true,
      unreadCount: 12,
      senderName: 'Sarah',
      imageUrl:
          'https://images.unsplash.com/photo-1522071820081-009f0129c71c?w=400',
    ),
    ChatModel(
      id: '8',
      name: 'Alice Johnson',
      lastMessage: 'Hey! Are you coming to the party tonight?',
      time: '2:34 PM',
      avatarText: 'AJ',
      avatarColor: '#E040FB',
      unreadCount: 3,
      isOnline: true,
      imageUrl:
          'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400',
    ),
    ChatModel(
      id: '9',
      name: 'Family Group',
      lastMessage: "Mom: Don't forget Sunday dinner!",
      time: 'Mon',
      avatarText: 'FG',
      isGroup: true,
      unreadCount: 5,
      senderName: 'Mom',
      imageUrl:
          'https://images.unsplash.com/photo-1511895426328-dc8714191300?w=400',
    ),
  ];

  static List<ChatModel> get groupChats =>
      allChats.where((c) => c.isGroup).toList();

  static const List<StoryModel> stories = [
    StoryModel(
      id: 'your',
      name: 'Your story',
      avatarText: 'Y',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400',
      profileImageUrl:
          'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400',
      isYourStory: true,
    ),
    StoryModel(
      id: 's1',
      name: 'Sonya',
      avatarText: 'S',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400',
      profileImageUrl:
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
    ),
    StoryModel(
      id: 's2',
      name: 'Adam',
      avatarText: 'A',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?w=400',
    ),
    StoryModel(
      id: 's3',
      name: 'Andrew',
      avatarText: 'An',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?w=400',
    ),
    StoryModel(
      id: 's4',
      name: 'Nicole',
      avatarText: 'N',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=400',
      profileImageUrl:
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
    ),
    StoryModel(
      id: 's5',
      name: 'Ashley',
      avatarText: 'As',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1448375240586-882707db888b?w=400',
      profileImageUrl:
          'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400',
    ),
    StoryModel(
      id: 's6',
      name: 'Michael',
      avatarText: 'M',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1433086966358-54859d0ed716?w=400',
    ),
    StoryModel(
      id: 's7',
      name: 'Damian',
      avatarText: 'D',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1518621736915-f3b1c41bfd00?w=400',
      profileImageUrl:
          'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
    ),
    StoryModel(
      id: 's8',
      name: 'Emma',
      avatarText: 'Em',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1491555103944-7c647fd857e6?w=400',
      profileImageUrl:
          'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400',
    ),
    StoryModel(
      id: 's9',
      name: 'James',
      avatarText: 'J',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?w=400',
    ),
    StoryModel(
      id: 's10',
      name: 'Olivia',
      avatarText: 'O',
      avatarColor: '#1565C0',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?w=400',
    ),
    StoryModel(
      id: 's11',
      name: 'William',
      avatarText: 'W',
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1433086966358-54859d0ed716?w=400',
    ),
  ];

  static const List<MessageModel> aliceMessages = [
    MessageModel(
      id: 'm1',
      content: "Hey! How's it going?",
      isOutgoing: false,
      time: '2:28 PM',
    ),
    MessageModel(
      id: 'm2',
      content: 'Pretty good! Just finished that project.',
      isOutgoing: true,
      time: '2:29 PM',
    ),
    MessageModel(
      id: 'm3',
      content: 'Check out this sunset photo!',
      isOutgoing: false,
      time: '2:30 PM',
      type: MessageType.image,
      imageUrl:
          'https://images.unsplash.com/photo-1518621736915-f3b1c41bfd00?w=400',
    ),
    MessageModel(
      id: 'm4',
      content: "Wow, that's beautiful!",
      isOutgoing: true,
      time: '2:31 PM',
    ),
    MessageModel(
      id: 'm5',
      content: '',
      isOutgoing: false,
      time: '2:32 PM',
      type: MessageType.audio,
      audioDuration: '7:05',
    ),
    MessageModel(
      id: 'm6',
      content: 'Are you coming to the party tonight?',
      isOutgoing: false,
      time: '2:34 PM',
    ),
    MessageModel(
      id: 'm7',
      content: "Yes! I'll be there!",
      isOutgoing: true,
      time: '2:35 PM',
    ),
  ];

  static const Map<String, List<MessageModel>> _chatMessages = {
    '1': [
      MessageModel(
          id: 'bc1',
          content: 'Has everyone read chapter 5?',
          isOutgoing: false,
          time: 'Wed 9:00 AM'),
      MessageModel(
          id: 'bc2',
          content: 'Yes! Loved the plot twist.',
          isOutgoing: true,
          time: 'Wed 9:05 AM'),
      MessageModel(
          id: 'bc3',
          content: 'Next read: The Great Gatsby',
          isOutgoing: false,
          time: 'Wed 9:10 AM'),
      MessageModel(
          id: 'bc4',
          content: 'Great choice! I reread it last year.',
          isOutgoing: true,
          time: 'Wed 9:15 AM'),
    ],
    '2': [
      MessageModel(
          id: 'cf1',
          content: 'Guys, remember graduation? 😂',
          isOutgoing: false,
          time: 'Tue 3:00 PM'),
      MessageModel(
          id: 'cf2',
          content: 'Haha those were the days!',
          isOutgoing: true,
          time: 'Tue 3:05 PM'),
      MessageModel(
          id: 'cf3',
          content: 'Jake: Reunion next month?',
          isOutgoing: false,
          time: 'Tue 3:10 PM'),
      MessageModel(
          id: 'cf4',
          content: "I'm in! Where are we meeting?",
          isOutgoing: true,
          time: 'Tue 3:12 PM'),
    ],
    '3': [
      MessageModel(
          id: 'cw1',
          content: 'Did you get my email?',
          isOutgoing: false,
          time: 'Yesterday 10:00 AM'),
      MessageModel(
          id: 'cw2',
          content: 'Just saw it, will reply shortly.',
          isOutgoing: true,
          time: 'Yesterday 10:05 AM'),
      MessageModel(
          id: 'cw3',
          content: 'See you at the meeting tomorrow!',
          isOutgoing: false,
          time: 'Yesterday 4:30 PM'),
      MessageModel(
          id: 'cw4',
          content: "Of course, I'll be there on time!",
          isOutgoing: true,
          time: 'Yesterday 4:35 PM'),
    ],
    '4': [
      MessageModel(
          id: 'bs1',
          content: 'Hey, do you have time for a quick review?',
          isOutgoing: false,
          time: 'Yesterday 1:00 PM'),
      MessageModel(
          id: 'bs2',
          content: 'Sure, send it over.',
          isOutgoing: true,
          time: 'Yesterday 1:05 PM'),
      MessageModel(
          id: 'bs3',
          content: 'Shared the PR link in Slack.',
          isOutgoing: false,
          time: 'Yesterday 1:20 PM'),
      MessageModel(
          id: 'bs4',
          content: 'Thanks for your help with the code review!',
          isOutgoing: false,
          time: 'Yesterday 3:00 PM'),
      MessageModel(
          id: 'bs5',
          content: 'Happy to help anytime 👍',
          isOutgoing: true,
          time: 'Yesterday 3:05 PM'),
    ],
    '5': [
      MessageModel(
          id: 'eg1',
          content: 'Happy birthday! 🎂🎉',
          isOutgoing: false,
          time: 'Sat 12:00 PM'),
      MessageModel(
          id: 'eg2',
          content: 'Thank you so much Eva! 😊',
          isOutgoing: true,
          time: 'Sat 12:10 PM'),
      MessageModel(
          id: 'eg3',
          content: 'Hope you have a wonderful day!',
          isOutgoing: false,
          time: 'Sat 12:11 PM'),
      MessageModel(
          id: 'eg4',
          content: "It's been great, had a small party!",
          isOutgoing: true,
          time: 'Sat 12:30 PM'),
    ],
    '6': [
      MessageModel(
          id: 'db1',
          content: 'Did you go to the concert last night?',
          isOutgoing: true,
          time: 'Sun 10:00 AM'),
      MessageModel(
          id: 'db2',
          content: 'Yes!! It was incredible!',
          isOutgoing: false,
          time: 'Sun 10:05 AM'),
      MessageModel(
          id: 'db3',
          content: 'The concert was amazing!',
          isOutgoing: false,
          time: 'Sun 10:06 AM'),
      MessageModel(
          id: 'db4',
          content: 'So jealous I missed it 😅',
          isOutgoing: true,
          time: 'Sun 10:10 AM'),
    ],
    '7': [
      MessageModel(
          id: 'tp1',
          content: 'Morning team! Stand-up in 10.',
          isOutgoing: false,
          time: '9:50 AM'),
      MessageModel(
          id: 'tp2', content: 'Be there!', isOutgoing: true, time: '9:52 AM'),
      MessageModel(
          id: 'tp3',
          content: 'Slides are updated in the shared drive.',
          isOutgoing: false,
          time: '12:30 PM'),
      MessageModel(
          id: 'tp4',
          content: 'Sarah: The presentation is ready for review',
          isOutgoing: false,
          time: '1:15 PM'),
      MessageModel(
          id: 'tp5',
          content: "Looks great, just left some comments.",
          isOutgoing: true,
          time: '1:45 PM'),
    ],
    '9': [
      MessageModel(
          id: 'fg1',
          content: 'Family dinner this Sunday at 7pm!',
          isOutgoing: false,
          time: 'Mon 8:00 AM'),
      MessageModel(
          id: 'fg2',
          content: "I'll bring dessert 🍰",
          isOutgoing: true,
          time: 'Mon 8:10 AM'),
      MessageModel(
          id: "fg3",
          content: "Mom: Don't forget Sunday dinner!",
          isOutgoing: false,
          time: 'Mon 9:00 AM'),
      MessageModel(
          id: 'fg4',
          content: "We'll be there, Mom!",
          isOutgoing: true,
          time: 'Mon 9:05 AM'),
    ],
  };

  /// Returns the message list for a given chat ID.
  /// Falls back to Alice's messages for chat '8'.
  static List<MessageModel> getMessages(String chatId) {
    if (chatId == '8') return aliceMessages;
    return _chatMessages[chatId] ?? aliceMessages;
  }
}
