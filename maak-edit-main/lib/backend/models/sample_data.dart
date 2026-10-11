// Sample/mock data for the Patient & Volunteer home experience.
// Replace these with real Supabase queries once the matching tables
// (volunteers, help_requests, messages, journey_steps) exist.

class SampleVolunteer {
  final String name;
  final String specialty;
  final String experience;
  final double rating;
  final int reviewCount;
  final String bio;
  final List<String> skills;

  const SampleVolunteer({
    required this.name,
    required this.specialty,
    required this.experience,
    required this.rating,
    required this.reviewCount,
    required this.bio,
    required this.skills,
  });
}

const List<SampleVolunteer> kSampleVolunteers = [
  SampleVolunteer(
    name: 'Sarah Al-Harbi',
    specialty: 'Diabetes',
    experience: '5 years experience',
    rating: 4.9,
    reviewCount: 23,
    bio:
        "I'm a diabetes patient and I've been living with it for 5 years. I'm here to support and guide others who are new to managing their condition.",
    skills: ['Arabic', 'English', 'Diabetes'],
  ),
  SampleVolunteer(
    name: 'Lina Abdullah',
    specialty: 'Cancer Support',
    experience: '3 years experience',
    rating: 4.8,
    reviewCount: 31,
    bio:
        'I walked the cancer treatment journey myself and now support others navigating diagnosis, treatment, and recovery.',
    skills: ['Arabic', 'English'],
  ),
  SampleVolunteer(
    name: 'Reem Al-Zahrani',
    specialty: 'Arthritis',
    experience: '4 years experience',
    rating: 4.7,
    reviewCount: 12,
    bio:
        'Living with rheumatoid arthritis for over a decade, I help others manage pain, mobility, and daily routines.',
    skills: ['Arabic'],
  ),
  SampleVolunteer(
    name: 'Nouf Faisal',
    specialty: 'Mental Health',
    experience: '6 years experience',
    rating: 4.9,
    reviewCount: 30,
    bio:
        'A mental health advocate with lived experience of anxiety and depression, here to listen without judgment.',
    skills: ['Arabic', 'English'],
  ),
];

class SampleRequest {
  final String name;
  final String gender;
  final int age;
  final double distanceKm;
  final String hoursPerWeek;
  final String category;
  final String description;

  const SampleRequest({
    required this.name,
    required this.gender,
    required this.age,
    required this.distanceKm,
    required this.hoursPerWeek,
    required this.category,
    required this.description,
  });
}

const List<SampleRequest> kSampleRequests = [
  SampleRequest(
    name: 'Support for diabetes management',
    gender: 'Male',
    age: 32,
    distanceKm: 2,
    hoursPerWeek: '2 hours/week',
    category: 'Chronic illness',
    description:
        "I was recently diagnosed with type 2 diabetes and I'm looking for someone who's been through it to help me understand daily management.",
  ),
  SampleRequest(
    name: 'Emotional support',
    gender: 'Female',
    age: 29,
    distanceKm: 4,
    hoursPerWeek: '1 hour/week',
    category: 'Mental health',
    description:
        "I'm looking for someone who can share their experience with anxiety and help me through this journey.",
  ),
  SampleRequest(
    name: 'Living with arthritis',
    gender: 'Female',
    age: 45,
    distanceKm: 6,
    hoursPerWeek: '2 hours/week',
    category: 'Chronic illness',
    description:
        'Looking for tips on managing daily pain and staying active despite arthritis flare-ups.',
  ),
  SampleRequest(
    name: 'Post-surgery recovery',
    gender: 'Female',
    age: 60,
    distanceKm: 3,
    hoursPerWeek: '1 hour/week',
    category: 'Recovery',
    description:
        'Recovering from surgery and would love a companion to talk to during the recovery period.',
  ),
];

class SampleMessageThread {
  final String name;
  final String lastMessage;
  final String time;
  final bool unread;

  const SampleMessageThread({
    required this.name,
    required this.lastMessage,
    required this.time,
    this.unread = false,
  });
}

const List<SampleMessageThread> kSampleThreads = [
  SampleMessageThread(
    name: 'Sarah Al-Harbi',
    lastMessage: 'See you at 4:00 PM today!',
    time: '9:41 AM',
    unread: true,
  ),
  SampleMessageThread(
    name: 'Lina Abdullah',
    lastMessage: 'Thank you so much for the tips.',
    time: 'Yesterday',
  ),
  SampleMessageThread(
    name: 'Reem Al-Zahrani',
    lastMessage: 'See you tomorrow!',
    time: 'Sep 8',
  ),
];

class SampleChatMessage {
  final bool fromMe;
  final String text;
  final String time;

  const SampleChatMessage({
    required this.fromMe,
    required this.text,
    required this.time,
  });
}

const List<SampleChatMessage> kSampleChatMessages = [
  SampleChatMessage(fromMe: false, text: 'Hi! Glad to connect with you 🌸', time: '9:00 AM'),
  SampleChatMessage(fromMe: true, text: "Hi Sarah, thank you for accepting my request!", time: '9:02 AM'),
  SampleChatMessage(fromMe: false, text: "Of course. How have you been feeling lately?", time: '9:05 AM'),
  SampleChatMessage(fromMe: true, text: "A bit overwhelmed, but hopeful.", time: '9:07 AM'),
];

class JourneyStep {
  final String title;
  final String subtitle;
  final JourneyStatus status;

  const JourneyStep({
    required this.title,
    required this.subtitle,
    required this.status,
  });
}

enum JourneyStatus { completed, inProgress, upcoming }

const List<JourneyStep> kSampleJourney = [
  JourneyStep(
    title: 'Welcome',
    subtitle: 'You joined the Ma\'ak community',
    status: JourneyStatus.completed,
  ),
  JourneyStep(
    title: 'Your First Chat',
    subtitle: 'You connected with your first volunteer',
    status: JourneyStatus.completed,
  ),
  JourneyStep(
    title: 'Building a Routine',
    subtitle: "You've had 2 chats this week",
    status: JourneyStatus.inProgress,
  ),
  JourneyStep(
    title: 'Ongoing Support',
    subtitle: 'Keep checking in with your volunteer',
    status: JourneyStatus.upcoming,
  ),
];

class ScheduleAppointment {
  final String time;
  final String title;
  final String status;

  const ScheduleAppointment({
    required this.time,
    required this.title,
    required this.status,
  });
}

const List<ScheduleAppointment> kSampleSchedule = [
  ScheduleAppointment(time: '10:00 AM - 10:30 AM', title: 'Patient chat', status: 'Confirmed'),
  ScheduleAppointment(time: '2:00 PM - 3:00 PM', title: 'Patient chat', status: 'Confirmed'),
  ScheduleAppointment(time: '6:00 PM - 7:00 PM', title: 'Patient chat', status: 'Pending'),
];
