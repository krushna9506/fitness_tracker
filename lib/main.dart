import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

const _lime = Color(0xffB7F55C);
const _ink = Color(0xff101314);
const _surface = Color(0xff191D1D);
const _surfaceSoft = Color(0xff232828);
const _muted = Color(0xffA9B2AF);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // AI parsing remains optional until a local .env file is supplied.
  }
  Object? error;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    error = e;
  }
  runApp(ProviderScope(child: PulseApp(error: error)));
}

class PulseApp extends StatelessWidget {
  const PulseApp({super.key, this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pulse',
      theme: base.copyWith(
        scaffoldBackgroundColor: _ink,
        colorScheme: const ColorScheme.dark(
          primary: _lime,
          onPrimary: _ink,
          surface: _surface,
          onSurface: Colors.white,
          error: Color(0xffFFB4AB),
        ),
        textTheme: GoogleFonts.manropeTextTheme(
          base.textTheme,
        ).apply(bodyColor: Colors.white, displayColor: Colors.white),
        appBarTheme: const AppBarTheme(backgroundColor: _ink, elevation: 0),
        cardTheme: CardThemeData(
          color: _surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceSoft,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xff303636)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _lime,
            foregroundColor: _ink,
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      home: error == null ? const AuthGate() : SetupProblem(error: error!),
    );
  }
}

class Workout {
  const Workout({
    required this.id,
    required this.type,
    required this.duration,
    required this.calories,
    required this.time,
    this.notes = '',
    this.intensity = 'Moderate',
    this.rpe = 3,
  });
  final String id;
  final String type;
  final int duration;
  final int calories;
  final DateTime time;
  final String notes;
  final String intensity;
  final int rpe;

  double get rpeMultiplier => switch (rpe) {
    1 => 1.0,
    2 => 1.3,
    3 => 1.6,
    4 => 2.0,
    5 => 2.5,
    _ => 1.6,
  };

  double get workloadScore => duration * rpeMultiplier;

  factory Workout.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final timestamp = data['timestamp'];
    return Workout(
      id: doc.id,
      type: data['exercise_type'] as String? ?? 'Workout',
      duration: (data['duration_minutes'] as num?)?.round() ?? 0,
      calories: (data['calories_burned'] as num?)?.round() ?? 0,
      time: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      notes: data['notes'] as String? ?? '',
      intensity: data['intensity'] as String? ?? 'Moderate',
      rpe: (data['rpe'] as num?)?.round() ?? 3,
    );
  }
}

class TrainingPlan {
  const TrainingPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.sessionsPerWeek,
    required this.minutes,
  });
  final String id;
  final String name;
  final String description;
  final int sessionsPerWeek;
  final int minutes;

  factory TrainingPlan.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return TrainingPlan(
      id: doc.id,
      name: data['name'] as String? ?? 'Training plan',
      description: data['description'] as String? ?? '',
      sessionsPerWeek: (data['sessions_per_week'] as num?)?.round() ?? 3,
      minutes: (data['minutes'] as num?)?.round() ?? 30,
    );
  }
}

class ExerciseStep {
  const ExerciseStep({
    required this.name,
    required this.instruction,
    required this.seconds,
    this.restSeconds = 20,
    this.reps,
  });
  final String name;
  final String instruction;
  final int seconds;
  final int restSeconds;
  final String? reps;
}

class GuidedWorkout {
  const GuidedWorkout({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.color,
    required this.met,
    required this.steps,
  });
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final Color color;
  final double met;
  final List<ExerciseStep> steps;

  int get totalSeconds => steps.fold<int>(
    0,
    (total, step) => total + step.seconds + step.restSeconds,
  );
}

const guidedWorkouts = [
  GuidedWorkout(
    id: 'full_body',
    title: 'Full body reset',
    subtitle: 'No equipment · strength & cardio',
    category: 'Bodyweight',
    icon: Icons.accessibility_new_rounded,
    color: Color(0xffB7F55C),
    met: 6.0,
    steps: [
      ExerciseStep(
        name: 'Jumping jacks',
        instruction: 'Land softly and keep a steady rhythm.',
        seconds: 40,
      ),
      ExerciseStep(
        name: 'Bodyweight squats',
        instruction: 'Keep your chest tall and knees tracking over toes.',
        seconds: 45,
        reps: '12 reps',
      ),
      ExerciseStep(
        name: 'Push-ups',
        instruction: 'Use knees or incline support whenever needed.',
        seconds: 40,
        reps: '8–12 reps',
      ),
      ExerciseStep(
        name: 'Mountain climbers',
        instruction: 'Brace your core and move at a controlled pace.',
        seconds: 40,
      ),
      ExerciseStep(
        name: 'Forearm plank',
        instruction: 'Keep your spine neutral and breathe steadily.',
        seconds: 35,
        restSeconds: 0,
      ),
    ],
  ),
  GuidedWorkout(
    id: 'core',
    title: 'Core builder',
    subtitle: 'No equipment · 5 focused moves',
    category: 'Bodyweight',
    icon: Icons.center_focus_strong_rounded,
    color: Color(0xff77C8FF),
    met: 4.0,
    steps: [
      ExerciseStep(
        name: 'Dead bug',
        instruction: 'Move opposite arm and leg without arching your back.',
        seconds: 40,
        reps: '10 reps',
      ),
      ExerciseStep(
        name: 'Bicycle crunches',
        instruction: 'Rotate through your ribs rather than pulling your neck.',
        seconds: 40,
      ),
      ExerciseStep(
        name: 'Leg raises',
        instruction: 'Lower only as far as you can maintain control.',
        seconds: 35,
        reps: '10 reps',
      ),
      ExerciseStep(
        name: 'Side plank · left',
        instruction: 'Stack shoulders and lift through your waist.',
        seconds: 30,
      ),
      ExerciseStep(
        name: 'Side plank · right',
        instruction: 'Stack shoulders and lift through your waist.',
        seconds: 30,
        restSeconds: 0,
      ),
    ],
  ),
  GuidedWorkout(
    id: 'legs',
    title: 'Legs & glutes',
    subtitle: 'No equipment · lower-body strength',
    category: 'Bodyweight',
    icon: Icons.directions_walk_rounded,
    color: Color(0xffE6A4FF),
    met: 5.5,
    steps: [
      ExerciseStep(
        name: 'Reverse lunges',
        instruction: 'Step back gently and keep your front heel grounded.',
        seconds: 45,
        reps: '10 each side',
      ),
      ExerciseStep(
        name: 'Glute bridges',
        instruction:
            'Squeeze at the top without overextending your lower back.',
        seconds: 40,
        reps: '15 reps',
      ),
      ExerciseStep(
        name: 'Wall sit',
        instruction: 'Keep your knees comfortable; rise earlier if needed.',
        seconds: 40,
      ),
      ExerciseStep(
        name: 'Calf raises',
        instruction: 'Pause at the top and lower with control.',
        seconds: 40,
        reps: '15 reps',
      ),
      ExerciseStep(
        name: 'Split squat hold',
        instruction: 'Choose a stable stance and breathe through the hold.',
        seconds: 30,
        restSeconds: 0,
      ),
    ],
  ),
  GuidedWorkout(
    id: 'upper',
    title: 'Upper body',
    subtitle: 'No equipment · chest, arms & back',
    category: 'Bodyweight',
    icon: Icons.fitness_center_rounded,
    color: Color(0xffFFB86B),
    met: 5.0,
    steps: [
      ExerciseStep(
        name: 'Incline push-ups',
        instruction: 'Use a stable surface and keep your body in one line.',
        seconds: 40,
        reps: '8–12 reps',
      ),
      ExerciseStep(
        name: 'Superman hold',
        instruction: 'Lift gently; avoid pinching your lower back.',
        seconds: 35,
      ),
      ExerciseStep(
        name: 'Triceps dips',
        instruction: 'Use a stable chair or choose wall push-ups instead.',
        seconds: 35,
        reps: '8–10 reps',
      ),
      ExerciseStep(
        name: 'Shoulder taps',
        instruction: 'Keep hips level and alternate slowly.',
        seconds: 40,
      ),
      ExerciseStep(
        name: 'Child’s pose',
        instruction: 'Breathe deeply and let your shoulders relax.',
        seconds: 35,
        restSeconds: 0,
      ),
    ],
  ),
  GuidedWorkout(
    id: 'mobility',
    title: 'Mobility flow',
    subtitle: 'Recovery · gentle movement',
    category: 'Mobility',
    icon: Icons.self_improvement_rounded,
    color: Color(0xff85E7C8),
    met: 2.8,
    steps: [
      ExerciseStep(
        name: 'Cat-cow',
        instruction: 'Move slowly with your breath.',
        seconds: 45,
      ),
      ExerciseStep(
        name: 'World’s greatest stretch',
        instruction: 'Keep the range comfortable on both sides.',
        seconds: 50,
      ),
      ExerciseStep(
        name: 'Hip flexor stretch',
        instruction: 'Gently tuck the pelvis; avoid forcing the stretch.',
        seconds: 40,
      ),
      ExerciseStep(
        name: 'Thoracic rotation',
        instruction: 'Follow your hand with your eyes and keep hips stable.',
        seconds: 40,
      ),
      ExerciseStep(
        name: 'Box breathing',
        instruction: 'Inhale, hold, exhale, hold — all at an easy pace.',
        seconds: 45,
        restSeconds: 0,
      ),
    ],
  ),
  GuidedWorkout(
    id: 'run',
    title: 'Outdoor run',
    subtitle: 'Cardio · pace yourself',
    category: 'Cardio',
    icon: Icons.directions_run_rounded,
    color: Color(0xffFFB86B),
    met: 9.8,
    steps: [
      ExerciseStep(
        name: 'Easy warm-up walk',
        instruction: 'Start easy and check how your body feels.',
        seconds: 180,
        restSeconds: 0,
      ),
      ExerciseStep(
        name: 'Steady run',
        instruction: 'Use a conversational pace; slow down if needed.',
        seconds: 600,
        restSeconds: 0,
      ),
      ExerciseStep(
        name: 'Easy cool-down walk',
        instruction: 'Let your breathing settle gradually.',
        seconds: 180,
        restSeconds: 0,
      ),
    ],
  ),
  GuidedWorkout(
    id: 'cycle',
    title: 'Cycling intervals',
    subtitle: 'Cardio · indoor or outdoor',
    category: 'Cardio',
    icon: Icons.directions_bike_rounded,
    color: Color(0xff77C8FF),
    met: 7.5,
    steps: [
      ExerciseStep(
        name: 'Easy spin',
        instruction: 'Settle into a light cadence.',
        seconds: 180,
        restSeconds: 0,
      ),
      ExerciseStep(
        name: 'Working interval',
        instruction: 'Increase effort while keeping your movement smooth.',
        seconds: 180,
        restSeconds: 45,
      ),
      ExerciseStep(
        name: 'Working interval',
        instruction: 'Adjust resistance to stay controlled.',
        seconds: 180,
        restSeconds: 45,
      ),
      ExerciseStep(
        name: 'Cool-down spin',
        instruction: 'Reduce resistance and recover gradually.',
        seconds: 180,
        restSeconds: 0,
      ),
    ],
  ),
  GuidedWorkout(
    id: 'swim',
    title: 'Swim rhythm',
    subtitle: 'Cardio · pool session',
    category: 'Cardio',
    icon: Icons.pool_rounded,
    color: Color(0xff4BB8FF),
    met: 8.0,
    steps: [
      ExerciseStep(
        name: 'Easy warm-up laps',
        instruction: 'Start with relaxed, consistent strokes.',
        seconds: 180,
        restSeconds: 30,
      ),
      ExerciseStep(
        name: 'Steady laps',
        instruction: 'Keep your breathing pattern comfortable.',
        seconds: 300,
        restSeconds: 30,
      ),
      ExerciseStep(
        name: 'Focused laps',
        instruction: 'Maintain form rather than chasing speed.',
        seconds: 240,
        restSeconds: 30,
      ),
      ExerciseStep(
        name: 'Easy cool-down',
        instruction: 'Finish with slow, relaxed laps.',
        seconds: 150,
        restSeconds: 0,
      ),
    ],
  ),
];

class WorkoutDraft {
  const WorkoutDraft({
    required this.exerciseType,
    required this.durationMinutes,
    required this.estimatedCalories,
    required this.usedMetFallback,
  });

  final String exerciseType;
  final int durationMinutes;
  final int estimatedCalories;
  final bool usedMetFallback;
}

class WorkoutParseException implements Exception {
  const WorkoutParseException(this.message);
  final String message;
}

/// Parses a short workout description with Gemini, then independently checks
/// calories with a deliberately simple and explainable MET calculation.
class NaturalLanguageWorkoutParser {
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.5-flash-lite:generateContent';

  Future<WorkoutDraft> parse(String description) async {
    final fallback = _metFallback(description);
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw const WorkoutParseException(
        'AI parsing is not configured. Use the fields below to log manually.',
      );
    }

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text': '''Extract a workout log from the user's text.
Return only the requested JSON object. Do not include Markdown, explanation,
or additional fields. Normalise exercise_type to a short title such as Run,
Walk, Cycle, Strength, Yoga, Swimming, or HIIT. duration_minutes and
estimated_calories must be positive whole numbers. If an exact duration is not
given, make a conservative 30-minute estimate. Estimate calories for a 70 kg
adult. User text: "$description"''',
                    },
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.1,
                'responseMimeType': 'application/json',
                'responseSchema': {
                  'type': 'OBJECT',
                  'properties': {
                    'exercise_type': {'type': 'STRING'},
                    'duration_minutes': {'type': 'INTEGER'},
                    'estimated_calories': {'type': 'INTEGER'},
                  },
                  'required': [
                    'exercise_type',
                    'duration_minutes',
                    'estimated_calories',
                  ],
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const WorkoutParseException(
        'AI parsing is unavailable. You can still log this workout manually.',
      );
    }

    if (response.statusCode == 429) {
      throw const WorkoutParseException(
        'The AI parser is busy right now. Please use the manual fields below.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const WorkoutParseException(
        'The AI parser could not read this workout. Please use the manual fields below.',
      );
    }

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final text =
          body['candidates'][0]['content']['parts'][0]['text'] as String;
      final cleaned = text
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      final type = _normaliseActivity(
        data['exercise_type']?.toString() ?? fallback.exerciseType,
      );
      final duration =
          (data['duration_minutes'] as num?)?.round() ??
          fallback.durationMinutes;
      final modelCalories = (data['estimated_calories'] as num?)?.round() ?? 0;
      final metEstimate = _estimateCalories(type, duration);
      final implausible =
          duration < 1 ||
          duration > 600 ||
          modelCalories < 1 ||
          modelCalories > duration * 20 ||
          (modelCalories - metEstimate).abs() >
              math.max(250, metEstimate * .85);
      return WorkoutDraft(
        exerciseType: type,
        durationMinutes: duration.clamp(1, 600),
        estimatedCalories: implausible ? metEstimate : modelCalories,
        usedMetFallback: implausible,
      );
    } catch (_) {
      throw const WorkoutParseException(
        'The AI returned an unreadable workout. Please use the manual fields below.',
      );
    }
  }

  WorkoutDraft _metFallback(String description) {
    final text = description.toLowerCase();
    final durationMatch = RegExp(
      r'(\d{1,3})\s*(?:min|mins|minute|minutes)\b',
    ).firstMatch(text);
    final duration = int.tryParse(durationMatch?.group(1) ?? '') ?? 30;
    final type = _normaliseActivity(text);
    return WorkoutDraft(
      exerciseType: type,
      durationMinutes: duration.clamp(1, 600),
      estimatedCalories: _estimateCalories(type, duration.clamp(1, 600)),
      usedMetFallback: true,
    );
  }
}

String _normaliseActivity(String value) {
  final text = value.toLowerCase();
  if (text.contains('run') || text.contains('jog') || text.contains('5k')) {
    return 'Run';
  }
  if (text.contains('cycl') || text.contains('bike')) return 'Cycle';
  if (text.contains('walk') || text.contains('hike')) return 'Walk';
  if (text.contains('yoga') || text.contains('stretch')) return 'Yoga';
  if (text.contains('swim')) return 'Swimming';
  if (text.contains('hiit') || text.contains('interval')) return 'HIIT';
  if (text.contains('strength') ||
      text.contains('upper body') ||
      text.contains('lower body') ||
      text.contains('weight')) {
    return 'Strength';
  }
  return 'Strength';
}

int _estimateCalories(String type, int minutes) {
  const met = {
    'Run': 9.8,
    'Cycle': 7.5,
    'Walk': 3.5,
    'Yoga': 3.0,
    'Swimming': 8.0,
    'HIIT': 8.5,
    'Strength': 5.0,
  };
  return ((met[type] ?? 5.0) * 70 * minutes / 60).round();
}

class AnomalyCheck {
  const AnomalyCheck({
    required this.proposedDailyCalories,
    required this.usualDailyCalories,
    required this.threshold,
  });
  final int proposedDailyCalories;
  final int usualDailyCalories;
  final double threshold;
}

class TrendAnalysis {
  const TrendAnalysis({
    required this.slope,
    required this.projectedWeeklyCalories,
    required this.weeklyTarget,
  });
  final double slope;
  final int projectedWeeklyCalories;
  final int weeklyTarget;
  bool get onTrack => projectedWeeklyCalories >= weeklyTarget;
  String get direction => slope > 5
      ? 'rising'
      : slope < -5
      ? 'easing'
      : 'steady';
}

class FitnessRepository {
  FitnessRepository(this._db);
  final FirebaseFirestore _db;

  final List<Workout> _localWorkouts = [
    Workout(
      id: 'w1',
      type: 'Morning Run',
      duration: 30,
      calories: 320,
      time: DateTime.now().subtract(const Duration(hours: 3)),
      intensity: 'Moderate',
      notes: 'Refreshing morning jog',
      rpe: 4,
    ),
    Workout(
      id: 'w2',
      type: 'HIIT Session',
      duration: 45,
      calories: 450,
      time: DateTime.now().subtract(const Duration(days: 1)),
      intensity: 'High',
      notes: 'Core and leg interval workout',
      rpe: 5,
    ),
    Workout(
      id: 'w3',
      type: 'Cycling',
      duration: 60,
      calories: 520,
      time: DateTime.now().subtract(const Duration(days: 3)),
      intensity: 'High',
      notes: 'Outdoor trail cycle',
      rpe: 4,
    ),
  ];

  final List<TrainingPlan> _localPlans = [
    const TrainingPlan(
      id: 'p1',
      name: '5K Builder',
      description: '3 runs per week to build endurance for your first 5K.',
      sessionsPerWeek: 3,
      minutes: 30,
    ),
    const TrainingPlan(
      id: 'p2',
      name: 'Strength Base',
      description: '3 full-body strength sessions per week.',
      sessionsPerWeek: 3,
      minutes: 45,
    ),
    const TrainingPlan(
      id: 'p3',
      name: 'Active Reset',
      description: 'Light mobility and active recovery routine.',
      sessionsPerWeek: 4,
      minutes: 20,
    ),
  ];

  final Map<String, dynamic> _localProfile = {
    'weekly_goal': 4,
    'weekly_calorie_goal': 2000,
    'water_intake_ml': 1500,
    'display_name': '',
  };

  DocumentReference<Map<String, dynamic>> _profile(String uid) =>
      _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> _workouts(String uid) =>
      _profile(uid).collection('workouts');
  CollectionReference<Map<String, dynamic>> _plans(String uid) =>
      _profile(uid).collection('plans');

  Stream<List<Workout>> workouts(String uid) async* {
    yield List<Workout>.unmodifiable(_localWorkouts);
    try {
      final snapStream = _workouts(uid).snapshots().timeout(const Duration(seconds: 2));
      await for (final snapshot in snapStream) {
        if (snapshot.docs.isNotEmpty) {
          final list = snapshot.docs.map(Workout.fromSnapshot).toList();
          list.sort((a, b) => b.time.compareTo(a.time));
          _localWorkouts.clear();
          _localWorkouts.addAll(list);
        }
        yield List<Workout>.unmodifiable(_localWorkouts);
      }
    } catch (_) {
      yield List<Workout>.unmodifiable(_localWorkouts);
    }
  }

  Stream<List<TrainingPlan>> plans(String uid) async* {
    yield List<TrainingPlan>.unmodifiable(_localPlans);
    try {
      final snapStream = _plans(uid).snapshots().timeout(const Duration(seconds: 2));
      await for (final snapshot in snapStream) {
        if (snapshot.docs.isNotEmpty) {
          final list = snapshot.docs.map(TrainingPlan.fromSnapshot).toList();
          _localPlans.clear();
          _localPlans.addAll(list);
        }
        yield List<TrainingPlan>.unmodifiable(_localPlans);
      }
    } catch (_) {
      yield List<TrainingPlan>.unmodifiable(_localPlans);
    }
  }

  Stream<Map<String, dynamic>> profile(String uid) async* {
    yield Map<String, dynamic>.unmodifiable(_localProfile);
    try {
      final snapStream = _profile(uid).snapshots().timeout(const Duration(seconds: 2));
      await for (final snapshot in snapStream) {
        final data = snapshot.data();
        if (data != null && data.isNotEmpty) {
          _localProfile.addAll(data);
        }
        yield Map<String, dynamic>.unmodifiable(_localProfile);
      }
    } catch (_) {
      yield Map<String, dynamic>.unmodifiable(_localProfile);
    }
  }

  Future<void> ensureProfile(User user) async {
    _localProfile['email'] = user.email ?? '';
    _localProfile['display_name'] = user.displayName ?? '';
    try {
      final ref = _profile(user.uid);
      final snap = await ref.get().timeout(const Duration(seconds: 2));
      if (!snap.exists) {
        await ref.set({
          'email': user.email,
          'display_name': user.displayName ?? '',
          'weekly_goal': 4,
          'weekly_calorie_goal': 2000,
          'created_at': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 2));
      } else if (snap.data() != null) {
        _localProfile.addAll(snap.data()!);
      }
    } catch (_) {}
  }

  Future<void> addWorkout(String uid, Workout workout) async {
    final newWorkout = Workout(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: workout.type,
      duration: workout.duration,
      calories: workout.calories,
      time: workout.time,
      notes: workout.notes,
      intensity: workout.intensity,
      rpe: workout.rpe,
    );
    _localWorkouts.insert(0, newWorkout);
    try {
      await _workouts(uid).add({
        'exercise_type': workout.type,
        'duration_minutes': workout.duration,
        'calories_burned': workout.calories,
        'timestamp': Timestamp.fromDate(workout.time),
        'notes': workout.notes,
        'intensity': workout.intensity,
        'rpe': workout.rpe,
        'created_at': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> deleteWorkout(String uid, String id) async {
    _localWorkouts.removeWhere((w) => w.id == id);
    try {
      await _workouts(uid).doc(id).delete().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> addPlan(String uid, TrainingPlan plan) async {
    final newPlan = TrainingPlan(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: plan.name,
      description: plan.description,
      sessionsPerWeek: plan.sessionsPerWeek,
      minutes: plan.minutes,
    );
    _localPlans.insert(0, newPlan);
    try {
      await _plans(uid).add({
        'name': plan.name,
        'description': plan.description,
        'sessions_per_week': plan.sessionsPerWeek,
        'minutes': plan.minutes,
        'created_at': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> deletePlan(String uid, String id) async {
    _localPlans.removeWhere((p) => p.id == id);
    try {
      await _plans(uid).doc(id).delete().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> setWeeklyGoal(String uid, int goal) async {
    _localProfile['weekly_goal'] = goal;
    try {
      await _profile(uid).set({'weekly_goal': goal}, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> setWeeklyCalorieGoal(String uid, int goal) async {
    _localProfile['weekly_calorie_goal'] = goal;
    try {
      await _profile(uid).set({'weekly_calorie_goal': goal}, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> updateWaterIntake(String uid, int amountMl) async {
    _localProfile['water_intake_ml'] = amountMl;
    try {
      await _profile(uid).set({
        'water_intake_ml': amountMl,
        'water_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> toggleChallengeDay(
    String uid,
    int dayNumber,
    List<int> currentDays,
  ) async {
    final updated = List<int>.from(currentDays);
    if (updated.contains(dayNumber)) {
      updated.remove(dayNumber);
    } else {
      updated.add(dayNumber);
    }
    await _profile(
      uid,
    ).set({'completed_challenge_days': updated}, SetOptions(merge: true));
  }

  Future<void> updateBodyMetrics(
    String uid,
    double heightCm,
    double weightKg,
  ) => _profile(uid).set({
    'height_cm': heightCm,
    'weight_kg': weightKg,
  }, SetOptions(merge: true));

  Future<AnomalyCheck?> anomalyCheck(String uid, Workout candidate) async {
    final candidateDay = DateUtils.dateOnly(candidate.time);
    final firstDay = candidateDay.subtract(const Duration(days: 28));
    final snapshot = await _workouts(uid)
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay),
        )
        .get();
    final totals = <DateTime, int>{
      for (var offset = 1; offset <= 28; offset++)
        candidateDay.subtract(Duration(days: offset)): 0,
    };
    var existingToday = 0;
    for (final document in snapshot.docs) {
      final workout = Workout.fromSnapshot(document);
      final day = DateUtils.dateOnly(workout.time);
      if (day == candidateDay) {
        existingToday += workout.calories;
      } else if (totals.containsKey(day)) {
        totals[day] = totals[day]! + workout.calories;
      }
    }
    final samples = totals.values.map((value) => value.toDouble()).toList();
    final mean =
        samples.fold<double>(0, (total, value) => total + value) /
        samples.length;
    final variance =
        samples.fold<double>(
          0,
          (total, value) => total + math.pow(value - mean, 2),
        ) /
        samples.length;
    final threshold = mean + math.max(2 * math.sqrt(variance), 300);
    final proposed = existingToday + candidate.calories;
    if (proposed > threshold) {
      return AnomalyCheck(
        proposedDailyCalories: proposed,
        usualDailyCalories: mean.round(),
        threshold: threshold,
      );
    }
    return null;
  }

  Future<void> seedDemo(String uid) async {
    if ((await _workouts(uid).limit(1).get()).docs.isNotEmpty) return;
    final batch = _db.batch();
    const types = [
      'Run',
      'Strength',
      'Cycle',
      'Yoga',
      'Walk',
      'Strength',
      'Run',
    ];
    for (var index = 0; index < 7; index++) {
      final date = DateTime.now().subtract(Duration(days: 6 - index));
      batch.set(_workouts(uid).doc(), {
        'exercise_type': types[index],
        'duration_minutes': 25 + index * 5,
        'calories_burned': 180 + index * 42,
        'timestamp': Timestamp.fromDate(date),
        'notes': 'Demo session',
        'intensity': index.isEven ? 'Moderate' : 'High',
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

final repositoryProvider = Provider(
  (_) => FitnessRepository(FirebaseFirestore.instance),
);
final workoutParserProvider = Provider((_) => NaturalLanguageWorkoutParser());
final authProvider = StreamProvider<User?>(
  (_) async* {
    try {
      yield FirebaseAuth.instance.currentUser;
      final authStream = FirebaseAuth.instance.authStateChanges().timeout(const Duration(seconds: 2));
      await for (final user in authStream) {
        yield user;
      }
    } catch (_) {
      yield FirebaseAuth.instance.currentUser;
    }
  },
);
final workoutsProvider = StreamProvider.family<List<Workout>, String>(
  (ref, uid) => ref.watch(repositoryProvider).workouts(uid),
);
final plansProvider = StreamProvider.family<List<TrainingPlan>, String>(
  (ref, uid) => ref.watch(repositoryProvider).plans(uid),
);
final profileProvider = StreamProvider.family<Map<String, dynamic>, String>(
  (ref, uid) => ref.watch(repositoryProvider).profile(uid),
);

class SetupProblem extends StatelessWidget {
  const SetupProblem({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => const AuthPage();
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(authProvider)
      .maybeWhen(
        data: (user) => user == null ? const AuthPage() : AppShell(user: user),
        orElse: () => const AuthPage(),
      );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createAccount = false;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_createAccount) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Could not authenticate.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      body: Row(
        children: [
          if (large)
            Expanded(
              flex: 6,
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xffD4FF8C),
                      Color(0xff79C6A1),
                      Color(0xff256F62),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Brand(dark: true),
                      const Spacer(),
                      const Text(
                        'Build momentum.\nEvery single day.',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 48,
                          height: 1.04,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const SizedBox(
                        width: 390,
                        child: Text(
                          'Plan your training, record every session, and keep your progress moving.',
                          style: TextStyle(
                            color: Color(0xff25453C),
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            flex: 5,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!large) ...[
                          const _Brand(),
                          const SizedBox(height: 54),
                        ],
                        Text(
                          _createAccount
                              ? 'Start your journey'
                              : 'Welcome back',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _createAccount
                              ? 'Create your private training space in seconds.'
                              : 'Your plan, progress, and next session are waiting.',
                          style: const TextStyle(color: _muted),
                        ),
                        const SizedBox(height: 30),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) =>
                              value != null && value.contains('@')
                              ? null
                              : 'Enter a valid email address',
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscurePassword,
                          autofillHints: [
                            _createAccount
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value != null && value.length >= 6
                              ? null
                              : 'Use at least 6 characters',
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Color(0xffFFB4AB)),
                            ),
                          ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _ink,
                                  ),
                                )
                              : Text(
                                  _createAccount ? 'Create account' : 'Sign in',
                                ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _createAccount = !_createAccount,
                                ),
                          child: Text(
                            _createAccount
                                ? 'Already have an account? Sign in'
                                : 'New to Pulse? Create an account',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.dark = false});
  final bool dark;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        height: 34,
        width: 34,
        decoration: BoxDecoration(
          color: dark ? _ink : _lime,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(Icons.bolt_rounded, color: dark ? _lime : _ink, size: 21),
      ),
      const SizedBox(width: 10),
      Text(
        'PULSE',
        style: TextStyle(
          color: dark ? _ink : Colors.white,
          letterSpacing: 2,
          fontWeight: FontWeight.w900,
          fontSize: 19,
        ),
      ),
    ],
  );
}

class GuidedWorkoutPicker extends StatefulWidget {
  const GuidedWorkoutPicker({super.key, required this.user});
  final User user;

  @override
  State<GuidedWorkoutPicker> createState() => _GuidedWorkoutPickerState();
}

class _GuidedWorkoutPickerState extends State<GuidedWorkoutPicker> {
  String _category = 'All';

  @override
  Widget build(BuildContext context) {
    final workouts = _category == 'All'
        ? guidedWorkouts
        : guidedWorkouts
              .where((workout) => workout.category == _category)
              .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Guided workouts',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
              children: [
                Text(
                  'Pick your next session',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Original guided routines with timers, recovery breaks, and live session tracking.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['All', 'Bodyweight', 'Cardio', 'Mobility']
                      .map(
                        (category) => ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 900
                        ? 3
                        : constraints.maxWidth >= 600
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 14) / columns;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: workouts
                          .map(
                            (workout) => SizedBox(
                              width: width,
                              child: _GuidedWorkoutCard(
                                workout: workout,
                                onStart: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GuidedSessionPage(
                                      user: widget.user,
                                      workout: workout,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuidedWorkoutCard extends StatelessWidget {
  const _GuidedWorkoutCard({required this.workout, required this.onStart});
  final GuidedWorkout workout;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onStart,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: workout.color.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(workout.icon, color: workout.color),
                ),
                const Spacer(),
                Text(
                  '${(workout.totalSeconds / 60).ceil()} min',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              workout.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(workout.subtitle, style: const TextStyle(color: _muted)),
            const SizedBox(height: 16),
            Text(
              '${workout.steps.length} exercises  •  ${workout.category}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start session'),
            ),
          ],
        ),
      ),
    ),
  );
}

class GuidedSessionPage extends ConsumerStatefulWidget {
  const GuidedSessionPage({
    super.key,
    required this.user,
    required this.workout,
  });
  final User user;
  final GuidedWorkout workout;

  @override
  ConsumerState<GuidedSessionPage> createState() => _GuidedSessionPageState();
}

class _GuidedSessionPageState extends ConsumerState<GuidedSessionPage> {
  Timer? _ticker;
  var _stepIndex = 0;
  var _remaining = 0;
  var _elapsed = 0;
  var _isRest = false;
  var _manualBreak = false;
  var _paused = false;
  var _saving = false;
  var _activeRemainingBeforeBreak = 0;

  ExerciseStep get _step => widget.workout.steps[_stepIndex];
  int get _phaseTotal =>
      _isRest ? (_manualBreak ? 60 : _step.restSeconds) : _step.seconds;

  @override
  void initState() {
    super.initState();
    _remaining = _step.seconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _paused || _saving) return;
    if (_remaining > 1) {
      setState(() {
        _remaining--;
        _elapsed++;
      });
    } else {
      setState(() => _elapsed++);
      _advancePhase();
    }
  }

  void _advancePhase() {
    if (_isRest && _manualBreak) {
      setState(() {
        _isRest = false;
        _manualBreak = false;
        _remaining = _activeRemainingBeforeBreak;
      });
      return;
    }
    if (!_isRest && _step.restSeconds > 0) {
      setState(() {
        _isRest = true;
        _remaining = _step.restSeconds;
      });
      return;
    }
    if (_stepIndex >= widget.workout.steps.length - 1) {
      _finish(completed: true);
      return;
    }
    setState(() {
      _stepIndex++;
      _isRest = false;
      _manualBreak = false;
      _remaining = _step.seconds;
    });
  }

  void _takeBreak() {
    setState(() {
      if (_isRest && _manualBreak) {
        _isRest = false;
        _manualBreak = false;
        _remaining = _activeRemainingBeforeBreak;
      } else {
        _activeRemainingBeforeBreak = _remaining;
        _isRest = true;
        _manualBreak = true;
        _remaining = 60;
      }
    });
  }

  void _restart() {
    setState(() {
      _stepIndex = 0;
      _remaining = widget.workout.steps.first.seconds;
      _elapsed = 0;
      _isRest = false;
      _manualBreak = false;
      _paused = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session reset to Step 1'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _finish({required bool completed}) async {
    if (_saving) return;
    _ticker?.cancel();
    final minutes = math.max(1, (_elapsed / 60).ceil());
    final calories = math.max(
      1,
      ((widget.workout.met * 70 * _elapsed) / 3600).round(),
    );
    int rpeRating = 7;
    final notesController = TextEditingController(
      text:
          'Guided session · ${completed ? 'completed' : 'ended early'} · ${_stepIndex + 1}/${widget.workout.steps.length} exercises',
    );

    final saved = await showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Finish ${widget.workout.title}?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryMetric(
                      label: 'Duration',
                      value: _formatSeconds(_elapsed),
                    ),
                    _SummaryMetric(label: 'Calories', value: '$calories kcal'),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'EFFORT RATING (RPE 1-10)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
                Slider(
                  value: rpeRating.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: 'RPE $rpeRating',
                  onChanged: (v) => setDialogState(() => rpeRating = v.round()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Session notes',
                    hintText: 'How did it feel?',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Discard', style: TextStyle(color: Color(0xffFFB4AB))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Resume'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save to Firestore'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      setState(() => _saving = true);
      await ref
          .read(repositoryProvider)
          .addWorkout(
            widget.user.uid,
            Workout(
              id: '',
              type: widget.workout.title,
              duration: minutes,
              calories: calories,
              time: DateTime.now(),
              intensity: rpeRating >= 8
                  ? 'High'
                  : (rpeRating >= 5 ? 'Moderate' : 'Easy'),
              notes: notesController.text,
              rpe: (rpeRating / 2).round().clamp(1, 5),
            ),
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${widget.workout.title} saved to Cloud Firestore!'),
        ),
      );
    } else if (saved == false) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workout = widget.workout;
    final progress = _phaseTotal == 0 ? 0.0 : 1 - (_remaining / _phaseTotal);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => _finish(completed: false),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          'Step ${_stepIndex + 1} of ${workout.steps.length}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _restart,
            tooltip: 'Restart session',
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value:
                        (_stepIndex + (_isRest ? .5 : 0)) /
                        workout.steps.length,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(20),
                    color: workout.color,
                    backgroundColor: _surfaceSoft,
                  ),
                  const Spacer(),
                  Text(
                    _isRest
                        ? (_manualBreak ? 'Take a breath' : 'Recovery')
                        : 'Now moving',
                    style: TextStyle(
                      color: _isRest ? const Color(0xff77C8FF) : workout.color,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    _isRest ? 'Rest' : _step.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isRest
                        ? 'Reset, hydrate, and prepare for the next move.'
                        : _step.instruction,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted, fontSize: 16),
                  ),
                  if (!_isRest &&
                      _step.reps != null &&
                      _step.reps!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Chip(
                      label: Text(_step.reps!),
                      avatar: const Icon(Icons.repeat_rounded, size: 17),
                    ),
                  ],
                  const SizedBox(height: 38),
                  SizedBox(
                    height: 210,
                    width: 210,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: progress.clamp(0, 1),
                          strokeWidth: 11,
                          backgroundColor: _surfaceSoft,
                          color: _isRest
                              ? const Color(0xff77C8FF)
                              : workout.color,
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatSeconds(_remaining),
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _paused
                                    ? 'PAUSED'
                                    : _isRest
                                    ? 'REST'
                                    : 'WORK',
                                style: TextStyle(
                                  color: _paused
                                      ? Colors.amber
                                      : (_isRest
                                            ? const Color(0xff77C8FF)
                                            : _lime),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Session time ${_formatSeconds(_elapsed)}',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _takeBreak,
                          icon: Icon(
                            _isRest && _manualBreak
                                ? Icons.play_arrow_rounded
                                : Icons.coffee_outlined,
                          ),
                          label: Text(
                            _isRest && _manualBreak
                                ? 'End Break'
                                : 'Take Break',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restart,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _advancePhase,
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text('Next'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _paused = !_paused),
                          icon: Icon(
                            _paused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                          ),
                          label: Text(_paused ? 'Resume' : 'Pause'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xffFF6B6B),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _finish(completed: false),
                          icon: const Icon(Icons.stop_circle_rounded),
                          label: const Text('Stop & Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// LIVE TRACKER & HOME WORKOUT (LEAP HEALTH) INDUSTRY-READY ENGINE
// -----------------------------------------------------------------------------

class LiveActivityOption {
  const LiveActivityOption({
    required this.id,
    required this.title,
    required this.category,
    required this.icon,
    required this.color,
    required this.met,
    required this.isMovement,
    required this.description,
  });

  final String id;
  final String title;
  final String category;
  final IconData icon;
  final Color color;
  final double met;
  final bool isMovement;
  final String description;
}

const liveActivities = [
  LiveActivityOption(
    id: 'outdoor_run',
    title: 'Outdoor Run',
    category: 'Outdoor',
    icon: Icons.directions_run_rounded,
    color: Color(0xffFFB86B),
    met: 9.8,
    isMovement: true,
    description:
        'Track pace, distance, heart rate, and calorie burn in real time.',
  ),
  LiveActivityOption(
    id: 'cycling',
    title: 'Outdoor Cycling',
    category: 'Outdoor',
    icon: Icons.directions_bike_rounded,
    color: Color(0xff77C8FF),
    met: 7.5,
    isMovement: true,
    description: 'Cadence, speed simulation, heart rate zones & energy output.',
  ),
  LiveActivityOption(
    id: 'swimming',
    title: 'Open Swimming',
    category: 'Outdoor',
    icon: Icons.pool_rounded,
    color: Color(0xff4BB8FF),
    met: 8.0,
    isMovement: true,
    description: 'Pool & open water stroke pacing with simulated lap splits.',
  ),
  LiveActivityOption(
    id: 'power_walk',
    title: 'Power Walk',
    category: 'Outdoor',
    icon: Icons.directions_walk_rounded,
    color: Color(0xffB7F55C),
    met: 4.5,
    isMovement: true,
    description: 'Low-impact steady cardio for endurance & active recovery.',
  ),
  LiveActivityOption(
    id: 'hiit_studio',
    title: 'HIIT Circuit',
    category: 'Indoor',
    icon: Icons.flash_on_rounded,
    color: Color(0xffFF6B6B),
    met: 8.5,
    isMovement: false,
    description:
        'High-intensity interval bursts to maximize EPOC calorie burn.',
  ),
  LiveActivityOption(
    id: 'jump_rope',
    title: 'Jump Rope',
    category: 'Indoor',
    icon: Icons.repeat_rounded,
    color: Color(0xffE6A4FF),
    met: 10.0,
    isMovement: false,
    description: 'Agility, footwork, and intense cardiovascular conditioning.',
  ),
  LiveActivityOption(
    id: 'rowing',
    title: 'Rowing Machine',
    category: 'Indoor',
    icon: Icons.rowing_rounded,
    color: Color(0xff85E7C8),
    met: 7.0,
    isMovement: true,
    description: 'Full-body cardiovascular stroke power and rhythm tracking.',
  ),
  LiveActivityOption(
    id: 'treadmill',
    title: 'Treadmill Run',
    category: 'Indoor',
    icon: Icons.fitness_center_rounded,
    color: Color(0xffFFB86B),
    met: 9.0,
    isMovement: true,
    description: 'Indoor running pace, incline simulation, and timer tracking.',
  ),
  LiveActivityOption(
    id: 'bodyweight_live',
    title: 'Bodyweight Freeform',
    category: 'Home',
    icon: Icons.accessibility_new_rounded,
    color: Color(0xffB7F55C),
    met: 5.5,
    isMovement: false,
    description: 'No equipment needed. Push-ups, squats, planks, and lunges.',
  ),
  LiveActivityOption(
    id: 'yoga_flow',
    title: 'Yoga & Mobility',
    category: 'Home',
    icon: Icons.self_improvement_rounded,
    color: Color(0xff77C8FF),
    met: 3.2,
    isMovement: false,
    description:
        'Mindful breathing, flexibility, posture hold, and core control.',
  ),
  LiveActivityOption(
    id: 'boxing_workout',
    title: 'Shadow Boxing',
    category: 'Indoor',
    icon: Icons.sports_mma_rounded,
    color: Color(0xffFF9F43),
    met: 8.0,
    isMovement: false,
    description: 'Rotational core power, upper-body stamina, and speed combos.',
  ),
  LiveActivityOption(
    id: 'pilates_core',
    title: 'Pilates Core',
    category: 'Home',
    icon: Icons.spa_rounded,
    color: Color(0xffC785EC),
    met: 4.0,
    isMovement: false,
    description:
        'Precision movement, spine alignment, and deep abdominal activation.',
  ),
];

class LiveTrackerSetupPage extends StatefulWidget {
  const LiveTrackerSetupPage({super.key, required this.user});
  final User user;

  @override
  State<LiveTrackerSetupPage> createState() => _LiveTrackerSetupPageState();
}

class _LiveTrackerSetupPageState extends State<LiveTrackerSetupPage> {
  LiveActivityOption _selected = liveActivities.first;
  String _targetMode = 'Open'; // 'Open', 'Time', 'Calories'
  int _targetValue = 30; // 30 mins or 300 kcal
  String _categoryFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final filtered = _categoryFilter == 'All'
        ? liveActivities
        : liveActivities.where((a) => a.category == _categoryFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Live Workout Studio',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 40),
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _lime.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.sensors_rounded,
                        color: _lime,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Live Session Mode',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const Text(
                            'Select your activity, set goals, and start live tracking with real-time feedback.',
                            style: TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Goal selector
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SESSION TARGET',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: _muted,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Open Goal'),
                              selected: _targetMode == 'Open',
                              onSelected: (_) =>
                                  setState(() => _targetMode = 'Open'),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Time Goal'),
                              selected: _targetMode == 'Time',
                              onSelected: (_) => setState(() {
                                _targetMode = 'Time';
                                _targetValue = 30;
                              }),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Calorie Goal'),
                              selected: _targetMode == 'Calories',
                              onSelected: (_) => setState(() {
                                _targetMode = 'Calories';
                                _targetValue = 300;
                              }),
                            ),
                          ],
                        ),
                        if (_targetMode != 'Open') ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text(
                                _targetMode == 'Time'
                                    ? 'Target: $_targetValue mins'
                                    : 'Target: $_targetValue kcal',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: _targetValue.toDouble(),
                                  min: _targetMode == 'Time' ? 5 : 50,
                                  max: _targetMode == 'Time' ? 120 : 1000,
                                  divisions: _targetMode == 'Time' ? 23 : 19,
                                  activeColor: _selected.color,
                                  onChanged: (v) =>
                                      setState(() => _targetValue = v.round()),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Activity Category Filters
                Wrap(
                  spacing: 8,
                  children: ['All', 'Outdoor', 'Indoor', 'Home']
                      .map(
                        (cat) => ChoiceChip(
                          label: Text(cat),
                          selected: _categoryFilter == cat,
                          onSelected: (_) =>
                              setState(() => _categoryFilter = cat),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                // Activity Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 900
                        ? 3
                        : constraints.maxWidth >= 600
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - (cols - 1) * 14) / cols;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: filtered
                          .map(
                            (act) => SizedBox(
                              width: width,
                              child: Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: _selected.id == act.id
                                        ? act.color
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => setState(() => _selected = act),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: act.color.withValues(
                                                  alpha: .18,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: Icon(
                                                act.icon,
                                                color: act.color,
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 9,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _surfaceSoft,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'MET ${act.met}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: _muted,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          act.title,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          act.description,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: _muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FreeformLiveWorkoutSession(
                          user: widget.user,
                          activity: _selected,
                          targetMode: _targetMode,
                          targetValue: _targetValue,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 28),
                    label: Text(
                      'START ${_selected.title.toUpperCase()} NOW',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LapSplit {
  LapSplit({
    required this.lapIndex,
    required this.durationSeconds,
    required this.distanceKm,
  });
  final int lapIndex;
  final int durationSeconds;
  final double distanceKm;
}

class FreeformLiveWorkoutSession extends ConsumerStatefulWidget {
  const FreeformLiveWorkoutSession({
    super.key,
    required this.user,
    required this.activity,
    required this.targetMode,
    required this.targetValue,
  });

  final User user;
  final LiveActivityOption activity;
  final String targetMode;
  final int targetValue;

  @override
  ConsumerState<FreeformLiveWorkoutSession> createState() =>
      _FreeformLiveWorkoutSessionState();
}

class _FreeformLiveWorkoutSessionState
    extends ConsumerState<FreeformLiveWorkoutSession> {
  Timer? _timer;
  int _countdown = 3; // Initial 3..2..1 launch countdown
  bool _countingDown = true;
  bool _paused = false;
  bool _isRest = false;
  int _restSeconds = 60;

  int _elapsedSeconds = 0;
  int _lastLapTime = 0;
  final List<LapSplit> _splits = [];

  // Live Simulated Metrics
  int _currentHeartRate = 80;
  String _hrZone = 'Warmup';
  Color _hrZoneColor = const Color(0xff77C8FF);

  // Live Coaching Messages
  final List<String> _coachTips = [
    "Keep a smooth and steady breathing rhythm.",
    "Form tip: Keep your shoulders relaxed and back straight.",
    "Stay hydrated! Take a sip of water whenever needed.",
    "Great effort! Stay focused on your movement technique.",
    "Engage your core to stabilize your posture.",
  ];
  int _tipIndex = 0;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        setState(() => _countingDown = false);
        _startLiveTicker();
      }
    });
  }

  void _startLiveTicker() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _paused) return;

    if (_isRest) {
      if (_restSeconds > 1) {
        setState(() => _restSeconds--);
      } else {
        setState(() {
          _isRest = false;
          _restSeconds = 60;
        });
      }
      return;
    }

    setState(() {
      _elapsedSeconds++;
      _updateLiveMetrics();
    });
  }

  void _updateLiveMetrics() {
    // Calculate simulated Heart Rate fluctuation
    final baseHr = (75 + widget.activity.met * 8).round();
    final floatValue = (math.sin(_elapsedSeconds / 7.0) * 8).round();
    _currentHeartRate = (baseHr + floatValue).clamp(60, 195);

    if (_currentHeartRate < 115) {
      _hrZone = 'Warmup';
      _hrZoneColor = const Color(0xff77C8FF);
    } else if (_currentHeartRate < 140) {
      _hrZone = 'Fat Burn';
      _hrZoneColor = _lime;
    } else if (_currentHeartRate < 165) {
      _hrZone = 'Cardio';
      _hrZoneColor = const Color(0xffFFB86B);
    } else {
      _hrZone = 'Peak';
      _hrZoneColor = const Color(0xffFF6B6B);
    }

    // Cycle AI coach tips every 20 seconds
    if (_elapsedSeconds % 20 == 0) {
      _tipIndex = (_tipIndex + 1) % _coachTips.length;
    }
  }

  int get _caloriesBurned =>
      ((widget.activity.met * 70 * _elapsedSeconds) / 3600).round();

  double get _distanceKm {
    if (!widget.activity.isMovement) return 0.0;
    // Speed km/h based on MET
    final speed = widget.activity.met * 1.1;
    return (speed * _elapsedSeconds) / 3600.0;
  }

  String get _paceString {
    if (!widget.activity.isMovement || _distanceKm < 0.05) return '--:--';
    final speedKmh = widget.activity.met * 1.1;
    final paceMin = 60.0 / speedKmh;
    final mins = paceMin.floor();
    final secs = ((paceMin - mins) * 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} /km';
  }

  void _recordLap() {
    final lapDuration = _elapsedSeconds - _lastLapTime;
    _lastLapTime = _elapsedSeconds;
    final lapDist = widget.activity.isMovement
        ? (widget.activity.met * 1.1 * lapDuration) / 3600.0
        : 0.0;
    setState(() {
      _splits.insert(
        0,
        LapSplit(
          lapIndex: _splits.length + 1,
          durationSeconds: lapDuration,
          distanceKm: lapDist,
        ),
      );
    });
  }

  void _takeBreak() {
    setState(() {
      _isRest = true;
      _restSeconds = 60;
    });
  }

  void _restart() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart workout?'),
        content: const Text(
          'This will reset your live time, calories, and lap splits.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _elapsedSeconds = 0;
                _lastLapTime = 0;
                _splits.clear();
                _paused = false;
                _isRest = false;
              });
            },
            child: const Text('Restart'),
          ),
        ],
      ),
    );
  }

  Future<void> _finishWorkout() async {
    _timer?.cancel();
    final durationMinutes = math.max(1, (_elapsedSeconds / 60).ceil());
    final calories = math.max(1, _caloriesBurned);
    int rpeRating = 7;
    final notesController = TextEditingController(
      text: 'Live Session • ${_splits.length} splits logged',
    );

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Finish ${widget.activity.title}?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryMetric(
                      label: 'Duration',
                      value: _formatSeconds(_elapsedSeconds),
                    ),
                    _SummaryMetric(label: 'Calories', value: '$calories kcal'),
                    if (widget.activity.isMovement)
                      _SummaryMetric(
                        label: 'Distance',
                        value: '${_distanceKm.toStringAsFixed(2)} km',
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'EFFORT RATING (RPE 1-10)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
                Slider(
                  value: rpeRating.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: 'RPE $rpeRating',
                  onChanged: (v) => setDialogState(() => rpeRating = v.round()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Session notes',
                    hintText: 'How did it feel?',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _startLiveTicker();
                Navigator.pop(ctx, false);
              },
              child: const Text('Resume'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save & Finish'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await ref
          .read(repositoryProvider)
          .addWorkout(
            widget.user.uid,
            Workout(
              id: '',
              type: widget.activity.title,
              duration: durationMinutes,
              calories: calories,
              time: DateTime.now(),
              intensity: rpeRating >= 8
                  ? 'High'
                  : (rpeRating >= 5 ? 'Moderate' : 'Easy'),
              notes: notesController.text,
              rpe: (rpeRating / 2).round().clamp(1, 5),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.activity.title} saved to activity!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final act = widget.activity;

    if (_countingDown) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'GET READY',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _muted,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: act.color.withValues(alpha: .18),
                  border: Border.all(color: act.color, width: 4),
                ),
                child: Center(
                  child: Text(
                    '$_countdown',
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      color: act.color,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                act.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          act.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: _restart,
            tooltip: 'Restart session',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                // Rest Overlay Ticker Banner
                if (_isRest)
                  Container(
                    width: double.infinity,
                    color: const Color(0xff77C8FF).withValues(alpha: .2),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.coffee_outlined,
                          color: Color(0xff77C8FF),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'RECOVERY BREAK: ${_restSeconds}s remaining',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xff77C8FF),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() => _isRest = false),
                          child: const Text('End Break'),
                        ),
                      ],
                    ),
                  ),
                // Coaching Tip Bar
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xff2D3434)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: _lime,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _coachTips[_tipIndex],
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Main Timer Display
                Text(
                  _formatSeconds(_elapsedSeconds),
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: 76,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                  ),
                ),
                if (_paused)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'PAUSED',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.amber,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                // Live Metrics Grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _LiveMetricTile(
                        icon: Icons.local_fire_department_rounded,
                        label: 'Calories',
                        value: '$_caloriesBurned',
                        unit: 'kcal',
                        accent: const Color(0xffFFB86B),
                      ),
                      _LiveMetricTile(
                        icon: Icons.favorite_rounded,
                        label: 'Heart Rate',
                        value: '$_currentHeartRate',
                        unit: 'BPM',
                        accent: _hrZoneColor,
                        badge: _hrZone,
                      ),
                      if (act.isMovement) ...[
                        _LiveMetricTile(
                          icon: Icons.route_rounded,
                          label: 'Distance',
                          value: _distanceKm.toStringAsFixed(2),
                          unit: 'km',
                          accent: const Color(0xff77C8FF),
                        ),
                        _LiveMetricTile(
                          icon: Icons.speed_rounded,
                          label: 'Pace',
                          value: _paceString,
                          unit: '',
                          accent: _lime,
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                // Lap splits list if any
                if (_splits.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text(
                          'LAP SPLITS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _muted,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_splits.length} laps recorded',
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: _splits.length,
                      itemBuilder: (ctx, i) {
                        final split = _splits[i];
                        return Container(
                          width: 130,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Lap ${split.lapIndex}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatSeconds(split.durationSeconds),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: act.color,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Controls Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _takeBreak,
                              icon: const Icon(Icons.coffee_outlined),
                              label: const Text('Take break'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _recordLap,
                              icon: const Icon(Icons.flag_outlined),
                              label: const Text('Lap / Split'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () =>
                                  setState(() => _paused = !_paused),
                              icon: Icon(
                                _paused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                              ),
                              label: Text(_paused ? 'Resume' : 'Pause'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xffFF6B6B),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _finishWorkout,
                              icon: const Icon(Icons.stop_circle_rounded),
                              label: const Text('Stop & Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveMetricTile extends StatelessWidget {
  const _LiveMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
    this.badge,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color accent;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: accent, size: 22),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(unit, style: const TextStyle(fontSize: 11, color: _muted)),
            ],
          ],
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
        if (badge != null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge!,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// LEAP HEALTH "HOME WORKOUT - NO EQUIPMENT" FEATURES & UI
// -----------------------------------------------------------------------------

class HomeWorkoutPlan {
  const HomeWorkoutPlan({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.exercisesCount,
    required this.durationMinutes,
    required this.targetMuscles,
    required this.exercises,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int exercisesCount;
  final int durationMinutes;
  final String targetMuscles;
  final List<ExerciseStep> exercises;
}

const homeWorkoutCategories = [
  HomeWorkoutPlan(
    id: 'full_body_no_equip',
    title: 'Full Body Classic',
    subtitle: 'Beginner to Advanced · 15 exercises',
    icon: Icons.accessibility_new_rounded,
    color: _lime,
    exercisesCount: 12,
    durationMinutes: 20,
    targetMuscles: 'Chest, Abs, Legs, Arms',
    exercises: [
      ExerciseStep(
        name: 'Jumping Jacks',
        instruction: 'Land soft, arms fully overhead.',
        seconds: 30,
      ),
      ExerciseStep(
        name: 'Incline Push-ups',
        instruction: 'Keep core tight, elbows 45 degrees.',
        seconds: 40,
        reps: '12 reps',
      ),
      ExerciseStep(
        name: 'Bodyweight Squats',
        instruction: 'Weight on heels, chest high.',
        seconds: 45,
        reps: '15 reps',
      ),
      ExerciseStep(
        name: 'Abdominal Crunches',
        instruction: 'Lift with core, do not strain neck.',
        seconds: 35,
        reps: '16 reps',
      ),
      ExerciseStep(
        name: 'Mountain Climbers',
        instruction: 'Keep hips down, drive knees up fast.',
        seconds: 30,
      ),
      ExerciseStep(
        name: 'Plank Hold',
        instruction: 'Keep spine flat, pull belly in.',
        seconds: 45,
        restSeconds: 0,
      ),
    ],
  ),
  HomeWorkoutPlan(
    id: 'abs_burner',
    title: 'Six Pack Abs Burner',
    subtitle: 'Core & Obliques strength',
    icon: Icons.center_focus_strong_rounded,
    color: Color(0xff77C8FF),
    exercisesCount: 10,
    durationMinutes: 15,
    targetMuscles: 'Rectus Abdominis, Obliques',
    exercises: [
      ExerciseStep(
        name: 'Bicycle Crunches',
        instruction: 'Elbow to opposite knee touch.',
        seconds: 40,
      ),
      ExerciseStep(
        name: 'Leg Raises',
        instruction: 'Lower slowly without arching lower back.',
        seconds: 35,
        reps: '12 reps',
      ),
      ExerciseStep(
        name: 'Russian Twists',
        instruction: 'Rotate torso side to side.',
        seconds: 40,
        reps: '20 reps',
      ),
      ExerciseStep(
        name: 'Plank Swings',
        instruction: 'Shift weight forward and back.',
        seconds: 30,
      ),
      ExerciseStep(
        name: 'Cobra Stretch',
        instruction: 'Relax hips and stretch abdominal wall.',
        seconds: 30,
        restSeconds: 0,
      ),
    ],
  ),
  HomeWorkoutPlan(
    id: 'chest_sculpt',
    title: 'Chest & Push Power',
    subtitle: 'Pectorals & Triceps builder',
    icon: Icons.fitness_center_rounded,
    color: Color(0xffFFB86B),
    exercisesCount: 8,
    durationMinutes: 14,
    targetMuscles: 'Chest, Front Deltoids, Triceps',
    exercises: [
      ExerciseStep(
        name: 'Standard Push-ups',
        instruction: 'Body rigid in a straight line.',
        seconds: 40,
        reps: '12 reps',
      ),
      ExerciseStep(
        name: 'Wide Push-ups',
        instruction: 'Hands wider than shoulder width.',
        seconds: 35,
        reps: '10 reps',
      ),
      ExerciseStep(
        name: 'Decline Push-ups',
        instruction: 'Elevate feet on chair/step.',
        seconds: 35,
        reps: '8 reps',
      ),
      ExerciseStep(
        name: 'Triceps Dips',
        instruction: 'Lower until elbows are at 90 degrees.',
        seconds: 40,
        reps: '12 reps',
      ),
      ExerciseStep(
        name: 'Chest Stretch',
        instruction: 'Open chest, pull shoulders back.',
        seconds: 30,
        restSeconds: 0,
      ),
    ],
  ),
  HomeWorkoutPlan(
    id: 'leg_power',
    title: 'Legs & Glutes Sculpt',
    subtitle: 'Quads, Hamstrings & Glutes',
    icon: Icons.directions_walk_rounded,
    color: Color(0xffE6A4FF),
    exercisesCount: 10,
    durationMinutes: 18,
    targetMuscles: 'Quadriceps, Glutes, Calves',
    exercises: [
      ExerciseStep(
        name: 'Squats',
        instruction: 'Push hips back, knees behind toes.',
        seconds: 45,
        reps: '15 reps',
      ),
      ExerciseStep(
        name: 'Alternating Lunges',
        instruction: 'Step forward, 90 deg knee bend.',
        seconds: 45,
        reps: '14 reps',
      ),
      ExerciseStep(
        name: 'Wall Sit Hold',
        instruction: 'Thighs parallel to the floor.',
        seconds: 40,
      ),
      ExerciseStep(
        name: 'Glute Bridges',
        instruction: 'Squeeze glutes at top hold.',
        seconds: 40,
        reps: '16 reps',
      ),
      ExerciseStep(
        name: 'Calf Raises',
        instruction: 'Pause at top extension.',
        seconds: 40,
        reps: '20 reps',
      ),
    ],
  ),
];

class HomeWorkoutHubPage extends StatefulWidget {
  const HomeWorkoutHubPage({super.key, required this.user});
  final User user;

  @override
  State<HomeWorkoutHubPage> createState() => _HomeWorkoutHubPageState();
}

class _HomeWorkoutHubPageState extends State<HomeWorkoutHubPage> {
  String _difficulty = 'Intermediate'; // Beginner, Intermediate, Advanced

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Home Workout · No Equipment',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xff1E2A22), Color(0xff151C18)],
                    ),
                    border: Border.all(color: _lime.withValues(alpha: .3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _lime.withValues(alpha: .2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.home_work_rounded,
                          color: _lime,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Zero Equipment Routines',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Target specific body parts with bodyweight exercises, visual form guides, and timers.',
                              style: TextStyle(color: _muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Level selector
                Row(
                  children: [
                    const Text(
                      'Difficulty Level: ',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: const Text('Beginner'),
                      selected: _difficulty == 'Beginner',
                      onSelected: (_) =>
                          setState(() => _difficulty = 'Beginner'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Intermediate'),
                      selected: _difficulty == 'Intermediate',
                      onSelected: (_) =>
                          setState(() => _difficulty = 'Intermediate'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Advanced'),
                      selected: _difficulty == 'Advanced',
                      onSelected: (_) =>
                          setState(() => _difficulty = 'Advanced'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Home Workout Cards
                ...homeWorkoutCategories.map(
                  (plan) => Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: plan.color.withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(plan.icon, color: plan.color),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      plan.title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      plan.subtitle,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GuidedSessionPage(
                                      user: widget.user,
                                      workout: GuidedWorkout(
                                        id: plan.id,
                                        title: '${plan.title} ($_difficulty)',
                                        subtitle:
                                            'No equipment · ${plan.targetMuscles}',
                                        category: 'Bodyweight',
                                        icon: plan.icon,
                                        color: plan.color,
                                        met: 6.0,
                                        steps: plan.exercises,
                                      ),
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Start'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Chip(
                                avatar: const Icon(
                                  Icons.fitness_center_rounded,
                                  size: 14,
                                ),
                                label: Text(plan.targetMuscles),
                              ),
                              const SizedBox(width: 8),
                              Chip(
                                avatar: const Icon(
                                  Icons.timer_outlined,
                                  size: 14,
                                ),
                                label: Text('${plan.durationMinutes} mins'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 30-DAY NO EQUIPMENT CHALLENGE
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// 30-DAY NO EQUIPMENT CHALLENGE
// -----------------------------------------------------------------------------

class Challenge30DayPage extends ConsumerWidget {
  const Challenge30DayPage({super.key, required this.user});
  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileValue = ref.watch(profileProvider(user.uid));
    final rawDays = profileValue.maybeWhen(
      data: (data) =>
          (data['completed_challenge_days'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          <int>[],
      orElse: () => <int>[],
    );
    final completedSet = Set<int>.from(rawDays);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '30-Day Bodyweight Challenge',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.military_tech_rounded,
                          color: _lime,
                          size: 40,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${completedSet.length} / 30 Days Completed',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: completedSet.length / 30.0,
                                color: _lime,
                                backgroundColor: _surfaceSoft,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 110,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemCount: 30,
                  itemBuilder: (ctx, index) {
                    final day = index + 1;
                    final isRestDay = day % 4 == 0;
                    final isDone = completedSet.contains(day);

                    return Card(
                      color: isDone
                          ? _lime.withValues(alpha: .2)
                          : (isRestDay ? _surfaceSoft : _surface),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isDone ? _lime : Colors.transparent,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          if (isRestDay) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Day rest! Rest and hydrate.'),
                              ),
                            );
                            return;
                          }
                          ref
                              .read(repositoryProvider)
                              .toggleChallengeDay(user.uid, day, rawDays);
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'DAY $day',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: isDone ? _lime : _muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Icon(
                              isDone
                                  ? Icons.check_circle_rounded
                                  : (isRestDay
                                        ? Icons.bed_rounded
                                        : Icons.play_circle_outline_rounded),
                              color: isDone
                                  ? _lime
                                  : (isRestDay ? Colors.amber : Colors.white),
                              size: 24,
                            ),
                            if (isRestDay)
                              const Text(
                                'REST',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.amber,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// WATER TRACKER & BMI CALCULATOR MODALS
// -----------------------------------------------------------------------------

class WaterTrackerCard extends ConsumerWidget {
  const WaterTrackerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final profileValue = ref.watch(profileProvider(user.uid));
    final currentMl = profileValue.maybeWhen(
      data: (data) => (data['water_intake_ml'] as num?)?.toInt() ?? 0,
      orElse: () => 0,
    );
    const targetMl = 2500;
    final progress = (currentMl / targetMl).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 6,
                    color: const Color(0xff77C8FF),
                    backgroundColor: _surfaceSoft,
                  ),
                  const Center(
                    child: Icon(
                      Icons.water_drop_rounded,
                      color: Color(0xff77C8FF),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hydration Tracker (Synced)',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$currentMl / $targetMl ml (${(progress * 100).round()}%)',
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: () {
                ref
                    .read(repositoryProvider)
                    .updateWaterIntake(
                      user.uid,
                      (currentMl + 250).clamp(0, 5000),
                    );
              },
              icon: const Icon(Icons.add_rounded),
              tooltip: '+250 ml',
            ),
          ],
        ),
      ),
    );
  }
}

class BmiCalculatorModal extends ConsumerStatefulWidget {
  const BmiCalculatorModal({super.key});

  @override
  ConsumerState<BmiCalculatorModal> createState() => _BmiCalculatorModalState();
}

class _BmiCalculatorModalState extends ConsumerState<BmiCalculatorModal> {
  double _heightCm = 175;
  double _weightKg = 70;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final profile = ref.read(profileProvider(user.uid)).asData?.value;
      if (profile != null) {
        _heightCm = (profile['height_cm'] as num?)?.toDouble() ?? 175;
        _weightKg = (profile['weight_kg'] as num?)?.toDouble() ?? 70;
      }
    }
  }

  double get _bmi => _weightKg / math.pow(_heightCm / 100.0, 2);

  String get _category {
    final val = _bmi;
    if (val < 18.5) return 'Underweight';
    if (val < 25.0) return 'Normal weight';
    if (val < 30.0) return 'Overweight';
    return 'Obese';
  }

  Color get _categoryColor {
    final val = _bmi;
    if (val < 18.5) return const Color(0xff77C8FF);
    if (val < 25.0) return _lime;
    if (val < 30.0) return const Color(0xffFFB86B);
    return const Color(0xffFF6B6B);
  }

  void _save() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      ref
          .read(repositoryProvider)
          .updateBodyMetrics(user.uid, _heightCm, _weightKg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'BMI & Body Health Calculator',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _categoryColor.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    _bmi.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: _categoryColor,
                    ),
                  ),
                  Text(
                    _category.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _categoryColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Height: ${_heightCm.round()} cm',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Expanded(
                  child: Slider(
                    value: _heightCm,
                    min: 120,
                    max: 220,
                    onChanged: (v) {
                      setState(() => _heightCm = v);
                      _save();
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  'Weight: ${_weightKg.round()} kg',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Expanded(
                  child: Slider(
                    value: _weightKg,
                    min: 30,
                    max: 180,
                    onChanged: (v) {
                      setState(() => _weightKg = v);
                      _save();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            _save();
            Navigator.pop(context);
          },
          child: const Text('Save & Close'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// SPORTS SCIENCE ANALYTICS, ACWR, POSE REP COUNTER & HANDS-FREE VOICE LAYER
// -----------------------------------------------------------------------------

class AcwrResult {
  const AcwrResult({
    required this.acuteLoad,
    required this.chronicLoad,
    required this.ratio,
    required this.statusLabel,
    required this.statusColor,
    required this.recommendation,
  });

  final double acuteLoad;
  final double chronicLoad;
  final double ratio;
  final String statusLabel;
  final Color statusColor;
  final String recommendation;
}

AcwrResult calculateAcwr(List<Workout> workouts) {
  final now = DateTime.now();
  final day7Ago = now.subtract(const Duration(days: 7));
  final day28Ago = now.subtract(const Duration(days: 28));

  double acuteLoad = 0.0;
  double chronicTotal = 0.0;

  DateTime? earliestWorkout;

  for (final w in workouts) {
    if (earliestWorkout == null || w.time.isBefore(earliestWorkout)) {
      earliestWorkout = w.time;
    }
    if (w.time.isAfter(day7Ago)) {
      acuteLoad += w.workloadScore;
    }
    if (w.time.isAfter(day28Ago)) {
      chronicTotal += w.workloadScore;
    }
  }

  // Calculate actual weeks active to prevent inflated ACWR for new users
  double weeksActive = 1.0;
  if (earliestWorkout != null) {
    final daysActive = now.difference(earliestWorkout).inDays;
    weeksActive = math.max(1.0, math.min(4.0, daysActive / 7.0));
  }

  final chronicLoad = math.max(chronicTotal / weeksActive, 1.0);
  final ratio = acuteLoad / chronicLoad;

  String label;
  Color color;
  String rec;

  if (ratio < 0.8) {
    label = 'Detraining / Under-training';
    color = const Color(0xff77C8FF);
    rec =
        'Training load is below optimal. Gradually increase volume to maintain adaptation.';
  } else if (ratio <= 1.3) {
    label = 'Sweet Spot (Optimal)';
    color = _lime;
    rec =
        'Workload is in the optimal sports-science zone for fitness gain with minimal injury risk.';
  } else if (ratio <= 1.5) {
    label = 'High Workload';
    color = const Color(0xffFFB86B);
    rec = 'Fatigue is building. Ensure proper sleep and hydration.';
  } else {
    label = 'Elevated Injury Risk — consider a lighter week';
    color = const Color(0xffFF6B6B);
    rec =
        'Acute load spike detected! Reduce volume this week to allow tissue recovery.';
  }

  return AcwrResult(
    acuteLoad: acuteLoad,
    chronicLoad: chronicLoad,
    ratio: ratio,
    statusLabel: label,
    statusColor: color,
    recommendation: rec,
  );
}

class AcwrCard extends StatelessWidget {
  const AcwrCard({super.key, required this.workouts});
  final List<Workout> workouts;

  @override
  Widget build(BuildContext context) {
    final res = calculateAcwr(workouts);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: res.statusColor.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    color: res.statusColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SPORTS SCIENCE ACWR INJURY RISK METER',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: _muted,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        'ACWR Ratio: ${res.ratio.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: res.statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: res.statusColor.withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    res.statusLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: res.statusColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _AcwrStatTile(
                  label: 'Acute Load (7-Day)',
                  value: res.acuteLoad.round().toString(),
                  unit: 'pts',
                ),
                _AcwrStatTile(
                  label: 'Chronic Load (28-Day Avg)',
                  value: res.chronicLoad.round().toString(),
                  unit: 'pts/wk',
                ),
                _AcwrStatTile(
                  label: 'Ratio Formula',
                  value: 'Acute / Chronic',
                  unit: '',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surfaceSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: _muted,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      res.recommendation,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcwrStatTile extends StatelessWidget {
  const _AcwrStatTile({
    required this.label,
    required this.value,
    required this.unit,
  });
  final String label, value, unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(unit, style: const TextStyle(fontSize: 11, color: _muted)),
            ],
          ],
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// JOINT-ANGLE VECTOR MATH ENGINE & POSE REP COUNTER
// -----------------------------------------------------------------------------

class Point2D {
  const Point2D(this.x, this.y);
  final double x;
  final double y;
}

class JointAngleCalculator {
  /// Calculates 3-point joint angle in degrees at vertex joint B (A -> B -> C)
  static double calculateAngle(Point2D a, Point2D b, Point2D c) {
    final ux = a.x - b.x;
    final uy = a.y - b.y;
    final vx = c.x - b.x;
    final vy = c.y - b.y;

    final dot = ux * vx + uy * vy;
    final magU = math.sqrt(ux * ux + uy * uy);
    final magV = math.sqrt(vx * vx + vy * vy);

    if (magU == 0 || magV == 0) return 180.0;

    final cosAngle = (dot / (magU * magV)).clamp(-1.0, 1.0);
    final angleRad = math.acos(cosAngle);
    return angleRad * 180.0 / math.pi;
  }
}

class PoseRepCounterStudio extends StatefulWidget {
  const PoseRepCounterStudio({super.key});

  @override
  State<PoseRepCounterStudio> createState() => _PoseRepCounterStudioState();
}

class _PoseRepCounterStudioState extends State<PoseRepCounterStudio> {
  String _exerciseMode = 'Squats'; // Squats or Push-ups
  int _repCount = 0;
  int _partialRepCount = 0;

  double _simulatedAngle = 170.0;
  double _minAngleInCurrentRep = 180.0;
  bool _isDescending = false;
  String _formFeedback = 'Standing ready — maintain tall spine';

  void _onAngleChange(double newAngle) {
    setState(() {
      _simulatedAngle = newAngle;

      if (newAngle < _minAngleInCurrentRep) {
        _minAngleInCurrentRep = newAngle;
      }

      if (newAngle < 140 && !_isDescending) {
        _isDescending = true;
        _formFeedback = 'Descending into move...';
      }

      // Check rep completion when ascending back above 160 deg
      if (_isDescending && newAngle > 160) {
        _isDescending = false;
        if (_minAngleInCurrentRep <= 90) {
          _repCount++;
          _formFeedback = 'FULL DEPTH REP COMPLETED! Great form.';
        } else if (_minAngleInCurrentRep <= 125) {
          _partialRepCount++;
          _formFeedback =
              'PARTIAL REP DETECTED — Didn\'t reach full 90° depth!';
        } else {
          _formFeedback = 'Shallow movement — drive deeper.';
        }
        _minAngleInCurrentRep = 180.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSquat = _exerciseMode == 'Squats';
    final keyA = isSquat ? 'Hip (Keypoint A)' : 'Shoulder (Keypoint A)';
    final keyB = isSquat ? 'Knee (Vertex B)' : 'Elbow (Vertex B)';
    final keyC = isSquat ? 'Ankle (Keypoint C)' : 'Wrist (Keypoint C)';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ML Pose Rep Counter',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Barbell / Bodyweight Squats'),
                      selected: isSquat,
                      onSelected: (_) => setState(() {
                        _exerciseMode = 'Squats';
                        _simulatedAngle = 170;
                        _minAngleInCurrentRep = 180;
                      }),
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: const Text('Push-ups'),
                      selected: !isSquat,
                      onSelected: (_) => setState(() {
                        _exerciseMode = 'Push-ups';
                        _simulatedAngle = 170;
                        _minAngleInCurrentRep = 180;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Main Rep Counter Display
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  '$_repCount',
                                  style: const TextStyle(
                                    fontSize: 54,
                                    fontWeight: FontWeight.w900,
                                    color: _lime,
                                  ),
                                ),
                                const Text(
                                  'Full Depth Reps',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                Text(
                                  '$_partialRepCount',
                                  style: const TextStyle(
                                    fontSize: 54,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xffFFB86B),
                                  ),
                                ),
                                const Text(
                                  'Partial Reps (Shallow)',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _formFeedback.contains('PARTIAL')
                                ? const Color(0xffFFB86B).withValues(alpha: .2)
                                : (_formFeedback.contains('FULL')
                                      ? _lime.withValues(alpha: .2)
                                      : _surfaceSoft),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _formFeedback,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _formFeedback.contains('PARTIAL')
                                  ? const Color(0xffFFB86B)
                                  : (_formFeedback.contains('FULL')
                                        ? _lime
                                        : _muted),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Manual Safety Net Override Controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Manual Override: ',
                              style: TextStyle(color: _muted, fontSize: 13),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: () => setState(() {
                                if (_repCount > 0) _repCount--;
                              }),
                              icon: const Icon(Icons.remove_rounded),
                              label: const Text('-1 Rep'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: () => setState(() => _repCount++),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('+1 Rep'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Vector Angle Live Simulator
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'JOINT ANGLE VECTOR STREAM (${_simulatedAngle.round()}°)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: _muted,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Landmark Vectors: $keyA -> $keyB -> $keyC',
                          style: const TextStyle(fontSize: 13, color: _muted),
                        ),
                        Slider(
                          value: _simulatedAngle,
                          min: 60,
                          max: 180,
                          activeColor: _simulatedAngle <= 90
                              ? _lime
                              : const Color(0xff77C8FF),
                          onChanged: _onAngleChange,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              '60° (Full Deep)',
                              style: TextStyle(fontSize: 11, color: _muted),
                            ),
                            Text(
                              '90° (Depth Line)',
                              style: TextStyle(
                                fontSize: 11,
                                color: _lime,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '180° (Standing)',
                              style: TextStyle(fontSize: 11, color: _muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HANDS-FREE VOICE SESSION ENGINE
// -----------------------------------------------------------------------------

class VoiceSetLoggerStudio extends StatefulWidget {
  const VoiceSetLoggerStudio({super.key, required this.user});
  final User user;

  @override
  State<VoiceSetLoggerStudio> createState() => _VoiceSetLoggerStudioState();
}

class _VoiceSetLoggerStudioState extends State<VoiceSetLoggerStudio> {
  final TextEditingController _voiceInputController = TextEditingController();
  final List<Map<String, dynamic>> _loggedSets = [];
  bool _isListening = false;

  void _parseVoiceInput(String text) {
    final lower = text.toLowerCase();
    final repsMatch = RegExp(r'(\d+)\s*(?:reps|rep)').firstMatch(lower);
    final weightMatch = RegExp(
      r'(\d+)\s*(?:kg|kilos|lbs|pound)',
    ).firstMatch(lower);
    final setMatch = RegExp(r'(?:set|next)\s*(\d+)').firstMatch(lower);

    final reps = int.tryParse(repsMatch?.group(1) ?? '') ?? 12;
    final weight = double.tryParse(weightMatch?.group(1) ?? '') ?? 40.0;
    final setNum =
        int.tryParse(setMatch?.group(1) ?? '') ?? (_loggedSets.length + 1);

    setState(() {
      _loggedSets.insert(0, {
        'set': setNum,
        'reps': reps,
        'weight': weight,
        'rawText': text,
        'timestamp': DateTime.now(),
      });
      _voiceInputController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Voice-Driven Hands-Free Logger',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () =>
                              setState(() => _isListening = !_isListening),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isListening
                                  ? const Color(0xffFF6B6B)
                                  : _lime.withValues(alpha: .2),
                              border: Border.all(
                                color: _isListening
                                    ? const Color(0xffFF6B6B)
                                    : _lime,
                                width: 3,
                              ),
                            ),
                            child: Icon(
                              _isListening
                                  ? Icons.mic_rounded
                                  : Icons.mic_none_rounded,
                              color: _isListening ? Colors.white : _lime,
                              size: 44,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _isListening
                              ? 'Listening... Say: "Next set 12 reps 40 kg"'
                              : 'Tap mic or type command below hands-free',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _voiceInputController,
                                decoration: const InputDecoration(
                                  hintText:
                                      'e.g. "next set, twelve reps, forty kilos"',
                                ),
                                onSubmitted: _parseVoiceInput,
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: () {
                                if (_voiceInputController.text.isNotEmpty) {
                                  _parseVoiceInput(_voiceInputController.text);
                                }
                              },
                              icon: const Icon(Icons.send_rounded),
                              label: const Text('Log'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'LOGGED SETS (REAL-TIME CONFIRMATION)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: _muted,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                if (_loggedSets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(
                      child: Text(
                        'No voice sets logged yet in this session.',
                        style: TextStyle(color: _muted),
                      ),
                    ),
                  )
                else
                  ..._loggedSets.map(
                    (s) => Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _lime.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'S${s['set']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: _lime,
                            ),
                          ),
                        ),
                        title: Text(
                          '${s['reps']} reps  •  ${s['weight']} kg',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          'Parsed from: "${s['rawText']}"',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                        trailing: const Icon(
                          Icons.check_circle_rounded,
                          color: _lime,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SMART GADGET & BLE TELEMETRY HUB
// -----------------------------------------------------------------------------

class SmartGadgetConnectModal extends StatefulWidget {
  const SmartGadgetConnectModal({super.key});

  @override
  State<SmartGadgetConnectModal> createState() =>
      _SmartGadgetConnectModalState();
}

class _SmartGadgetConnectModalState extends State<SmartGadgetConnectModal> {
  bool _connected = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Smart Gadgets & BLE Telemetry',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surfaceSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bluetooth_connected_rounded,
                    color: Color(0xff77C8FF),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BLE Heart Rate GATT (0x180D)',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Compatible with Polar H10, Garmin, Smart Bands',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _connected,
                    onChanged: (v) => setState(() => _connected = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'DISCOVERED SMART DEVICES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: _muted,
              ),
            ),
            const SizedBox(height: 8),
            _GadgetTile(
              name: 'Polar H10 Chest Strap',
              type: 'BLE Heart Rate (0x180D)',
              connected: _connected,
            ),
            const _GadgetTile(
              name: 'Garmin Vector Cadence',
              type: 'BLE Cycling Power (0x1818)',
              connected: false,
            ),
            const _GadgetTile(
              name: 'Smart Gym Rack IoT',
              type: 'Local Wi-Fi Telemetry Stream',
              connected: false,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _GadgetTile extends StatelessWidget {
  const _GadgetTile({
    required this.name,
    required this.type,
    required this.connected,
  });
  final String name, type;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            connected
                ? Icons.bluetooth_audio_rounded
                : Icons.bluetooth_disabled_rounded,
            color: connected ? _lime : _muted,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(type, style: const TextStyle(fontSize: 11, color: _muted)),
              ],
            ),
          ),
          Text(
            connected ? 'Connected' : 'Pair',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: connected ? _lime : _muted,
            ),
          ),
        ],
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.user});
  final User user;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(repositoryProvider).ensureProfile(widget.user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final page = IndexedStack(
      index: _index,
      children: [
        DashboardPage(
          user: widget.user,
          onNavigate: (value) => setState(() => _index = value),
        ),
        ActivityPage(user: widget.user),
        PlansPage(user: widget.user),
        InsightsPage(user: widget.user),
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              _SideNavigation(
                index: _index,
                onChanged: (value) => setState(() => _index = value),
              ),
            Expanded(child: page),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bolt_outlined),
                  label: 'Activity',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Plans',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  label: 'Insights',
                ),
              ],
            ),
      floatingActionButton: _index < 2
          ? FloatingActionButton.extended(
              onPressed: () => showWorkoutSheet(context, ref, widget.user.uid),
              backgroundColor: _lime,
              foregroundColor: _ink,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Log workout',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
    );
  }
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    width: 226,
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: Color(0xff272D2D))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(26, 30, 18, 36),
          child: _Brand(),
        ),
        _NavItem(
          icon: Icons.grid_view_rounded,
          label: 'Overview',
          selected: index == 0,
          onTap: () => onChanged(0),
        ),
        _NavItem(
          icon: Icons.bolt_outlined,
          label: 'Activity',
          selected: index == 1,
          onTap: () => onChanged(1),
        ),
        _NavItem(
          icon: Icons.calendar_month_outlined,
          label: 'Plans',
          selected: index == 2,
          onTap: () => onChanged(2),
        ),
        _NavItem(
          icon: Icons.insights_outlined,
          label: 'Insights',
          selected: index == 3,
          onTap: () => onChanged(3),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(18),
          child: TextButton.icon(
            onPressed: FirebaseAuth.instance.signOut,
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Sign out'),
          ),
        ),
      ],
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    child: Material(
      color: selected ? const Color(0xff293325) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: selected ? _lime : _muted),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PageLayout extends StatelessWidget {
  const PageLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 110),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(subtitle, style: const TextStyle(color: _muted)),
                    ],
                  ),
                ),
                if (action case final Widget action) action,
              ],
            ),
            const SizedBox(height: 28),
            child,
          ],
        ),
      ),
    ),
  );
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({
    super.key,
    required this.user,
    required this.onNavigate,
  });
  final User user;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutValue = ref.watch(workoutsProvider(user.uid));
    final profile = ref.watch(profileProvider(user.uid));
    return PageLayout(
      title: _greeting(user),
      subtitle: 'Here is your training pulse for today.',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _lime,
              foregroundColor: _ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LiveTrackerSetupPage(user: user),
              ),
            ),
            icon: const Icon(Icons.sensors_rounded, size: 20),
            label: const Text(
              'Live Studio',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Home Workout (No Equipment)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HomeWorkoutHubPage(user: user)),
            ),
            icon: const Icon(Icons.home_work_outlined),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () => onNavigate(3),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      child: workoutValue.when(
        loading: () => const _LoadingPanel(),
        error: (error, _) => _DataError(error: error),
        data: (workouts) {
          final goal = profile.maybeWhen(
            data: (data) => (data['weekly_goal'] as num?)?.toInt() ?? 4,
            orElse: () => 4,
          );
          return _DashboardContent(
            workouts: workouts,
            goal: goal,
            uid: user.uid,
            onNavigate: onNavigate,
          );
        },
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({
    required this.workouts,
    required this.goal,
    required this.uid,
    required this.onNavigate,
  });
  final List<Workout> workouts;
  final int goal;
  final String uid;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = _thisWeek(workouts);
    final today = workouts
        .where((workout) => DateUtils.isSameDay(workout.time, DateTime.now()))
        .toList();
    final calories = week.fold(0, (total, workout) => total + workout.calories);
    final minutes = week.fold(0, (total, workout) => total + workout.duration);
    final streak = _streak(workouts);
    final small = MediaQuery.sizeOf(context).width < 620;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live Workout Studio & Home Workout Hero Banner
        Card(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xff233325), Color(0xff161E1A)],
              ),
              border: Border.all(color: _lime.withValues(alpha: .3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _lime.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: _lime,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'LIVE TRACKER & HOME WORKOUT STUDIO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: _lime,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'Real-time workouts, bodyweight plans & live tracking',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _lime,
                        foregroundColor: _ink,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveTrackerSetupPage(
                            user: FirebaseAuth.instance.currentUser!,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.sensors_rounded, size: 18),
                      label: const Text('Start Live Outdoor / Gym Track'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HomeWorkoutHubPage(
                            user: FirebaseAuth.instance.currentUser!,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.home_work_rounded, size: 18),
                      label: const Text('Home Workout (No Equipment)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VoiceSetLoggerStudio(
                            user: FirebaseAuth.instance.currentUser!,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.mic_rounded, size: 18),
                      label: const Text('Voice Logger'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PoseRepCounterStudio(),
                        ),
                      ),
                      icon: const Icon(
                        Icons.accessibility_new_rounded,
                        size: 18,
                      ),
                      label: const Text('ML Pose Counter'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const SmartGadgetConnectModal(),
                      ),
                      icon: const Icon(Icons.bluetooth_audio_rounded, size: 18),
                      label: const Text('Smart Gadgets (BLE/WiFi)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Challenge30DayPage(
                            user: FirebaseAuth.instance.currentUser!,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.military_tech_rounded, size: 18),
                      label: const Text('30-Day Challenge'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const BmiCalculatorModal(),
                      ),
                      icon: const Icon(Icons.calculate_outlined, size: 18),
                      label: const Text('BMI Meter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Hydration Widget Card
        const WaterTrackerCard(),
        const SizedBox(height: 24),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              label: 'Weekly sessions',
              value: '${week.length}/$goal',
              detail: goal == 0
                  ? 'No target set'
                  : '${math.min(100, (week.length / goal * 100).round())}% of goal',
              icon: Icons.flag_outlined,
              accent: _lime,
            ),
            _MetricCard(
              label: 'Calories burned',
              value: _number(calories),
              detail: 'This week',
              icon: Icons.local_fire_department_outlined,
              accent: const Color(0xffFFB86B),
            ),
            _MetricCard(
              label: 'Active minutes',
              value: '$minutes',
              detail: 'This week',
              icon: Icons.timer_outlined,
              accent: const Color(0xff77C8FF),
            ),
            _MetricCard(
              label: 'Current streak',
              value: '$streak days',
              detail: streak == 0 ? 'Log a session today' : 'Keep it moving',
              icon: Icons.bolt_outlined,
              accent: const Color(0xffE6A4FF),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (small) ...[
          _WeeklyChart(workouts: workouts),
          const SizedBox(height: 18),
          _TodayCard(workouts: today, onViewAll: () => onNavigate(1)),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: _WeeklyChart(workouts: workouts)),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: _TodayCard(
                  workouts: today,
                  onViewAll: () => onNavigate(1),
                ),
              ),
            ],
          ),
        const SizedBox(height: 24),
        Text(
          'Quick start',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _QuickStart(
              icon: Icons.directions_run_rounded,
              label: 'Run',
              onTap: () => showWorkoutSheet(context, ref, uid, type: 'Run'),
            ),
            _QuickStart(
              icon: Icons.fitness_center_rounded,
              label: 'Strength',
              onTap: () =>
                  showWorkoutSheet(context, ref, uid, type: 'Strength'),
            ),
            _QuickStart(
              icon: Icons.directions_bike_rounded,
              label: 'Cycle',
              onTap: () => showWorkoutSheet(context, ref, uid, type: 'Cycle'),
            ),
            _QuickStart(
              icon: Icons.self_improvement_rounded,
              label: 'Yoga',
              onTap: () => showWorkoutSheet(context, ref, uid, type: 'Yoga'),
            ),
          ],
        ),
        if (workouts.isEmpty) ...[
          const SizedBox(height: 26),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: _lime),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Want to explore the dashboard first? Add a week of private demo sessions.',
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.read(repositoryProvider).seedDemo(uid),
                    child: const Text('Add demo'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.accent,
  });
  final String label, value, detail;
  final IconData icon;
  final Color accent;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 235,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(height: 18),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
      ),
    ),
  );
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.workouts});
  final List<Workout> workouts;
  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      7,
      (index) => DateUtils.dateOnly(
        DateTime.now().subtract(Duration(days: 6 - index)),
      ),
    );
    final values = days
        .map(
          (day) => workouts
              .where((w) => DateUtils.isSameDay(w.time, day))
              .fold<int>(0, (total, workout) => total + workout.calories),
        )
        .toList();
    final maxValue = math.max(400, values.fold(0, math.max)).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly energy',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Calories burned over the last 7 days',
                        style: TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.more_horiz_rounded, color: _muted),
              ],
            ),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  maxY: maxValue * 1.2,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxValue / 3,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: Color(0xff2C3333), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                          final index = value.toInt();
                          return Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Text(
                              index >= 0 && index < 7 ? labels[index] : '',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(
                    7,
                    (index) => BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: values[index].toDouble(),
                          width: 18,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                          color: index == 6 ? _lime : const Color(0xff4D6256),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.workouts, required this.onViewAll});
  final List<Workout> workouts;
  final VoidCallback onViewAll;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Today's activity",
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(onPressed: onViewAll, child: const Text('See all')),
            ],
          ),
          const SizedBox(height: 7),
          if (workouts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 39),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.timer_outlined, color: _muted, size: 32),
                    const SizedBox(height: 10),
                    const Text(
                      'No session yet',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Make today count.',
                      style: TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
            )
          else
            ...workouts.take(3).map((workout) => _WorkoutRow(workout: workout)),
        ],
      ),
    ),
  );
}

class _QuickStart extends StatelessWidget {
  const _QuickStart({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: 142,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xff2D3434)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _lime, size: 20),
          const SizedBox(width: 9),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    ),
  );
}

class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key, required this.user});
  final User user;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageLayout(
    title: 'Activity history',
    subtitle: 'Every session you log is saved here in real time.',
    action: OutlinedButton.icon(
      onPressed: () => showWorkoutSheet(context, ref, user.uid),
      icon: const Icon(Icons.add),
      label: const Text('Add activity'),
    ),
    child: ref
        .watch(workoutsProvider(user.uid))
        .when(
          loading: () => const _LoadingPanel(),
          error: (error, _) => _DataError(error: error),
          data: (workouts) => workouts.isEmpty
              ? _EmptyActivity(
                  onAdd: () => showWorkoutSheet(context, ref, user.uid),
                )
              : _ActivityList(user: user, workouts: workouts),
        ),
  );
}

class _ActivityList extends ConsumerWidget {
  const _ActivityList({required this.user, required this.workouts});
  final User user;
  final List<Workout> workouts;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <String, List<Workout>>{};
    for (final workout in workouts) {
      final key = _dateLabel(workout.time);
      (groups[key] ??= []).add(workout);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Card(
                    child: Column(
                      children: entry.value
                          .map(
                            (workout) => _WorkoutRow(
                              workout: workout,
                              expanded: true,
                              onDelete: () => _confirmDelete(
                                context,
                                ref,
                                user.uid,
                                workout,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({
    required this.workout,
    this.expanded = false,
    this.onDelete,
  });
  final Workout workout;
  final bool expanded;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.symmetric(
      horizontal: expanded ? 18 : 0,
      vertical: 5,
    ),
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _activityColor(workout.type).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        _activityIcon(workout.type),
        color: _activityColor(workout.type),
      ),
    ),
    title: Text(
      workout.type,
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text(
      '${workout.duration} min  •  ${workout.intensity}${workout.notes.isEmpty ? '' : '  •  ${workout.notes}'}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: _muted),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${workout.calories} kcal',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        if (onDelete != null)
          PopupMenuButton<String>(
            onSelected: (_) => onDelete!(),
            icon: const Icon(Icons.more_vert, color: _muted),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete activity')),
            ],
          ),
      ],
    ),
  );
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(42),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.route_outlined, size: 48, color: _lime),
            const SizedBox(height: 16),
            Text(
              'Your activity feed is ready',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Log your first workout to begin building your training history.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Log a workout'),
            ),
          ],
        ),
      ),
    ),
  );
}

class PlansPage extends ConsumerWidget {
  const PlansPage({super.key, required this.user});
  final User user;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageLayout(
    title: 'Training plans',
    subtitle: 'Build a repeatable routine around the way you want to train.',
    action: OutlinedButton.icon(
      onPressed: () => showPlanSheet(context, ref, user.uid),
      icon: const Icon(Icons.add),
      label: const Text('New plan'),
    ),
    child: ref
        .watch(plansProvider(user.uid))
        .when(
          loading: () => const _LoadingPanel(),
          error: (error, _) => _DataError(error: error),
          data: (plans) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (plans.isNotEmpty) ...[
                Text(
                  'Your plans',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: plans
                      .map((plan) => _PlanCard(plan: plan, uid: user.uid))
                      .toList(),
                ),
                const SizedBox(height: 30),
              ],
              Text(
                plans.isEmpty ? 'Start with a plan' : 'Plan ideas',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use a starting point or create a plan that fits your schedule.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _Recommendation(
                    title: '5K Builder',
                    detail: '3 runs / week · 30 min',
                    icon: Icons.directions_run_rounded,
                    onTap: () => showPlanSheet(context, ref, user.uid, initialName: '5K Builder'),
                  ),
                  _Recommendation(
                    title: 'Strength Base',
                    detail: '3 sessions / week · 45 min',
                    icon: Icons.fitness_center_rounded,
                    onTap: () => showPlanSheet(context, ref, user.uid, initialName: 'Strength Base'),
                  ),
                  _Recommendation(
                    title: 'Active reset',
                    detail: '4 sessions / week · 20 min',
                    icon: Icons.self_improvement_rounded,
                    onTap: () => showPlanSheet(context, ref, user.uid, initialName: 'Active reset'),
                  ),
                ],
              ),
            ],
          ),
        ),
  );
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan, required this.uid});
  final TrainingPlan plan;
  final String uid;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    width: 310,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _lime.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: _lime),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: (_) =>
                      ref.read(repositoryProvider).deletePlan(uid, plan.id),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete plan')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              plan.name,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              plan.description.isEmpty
                  ? 'A custom plan made for your next goal.'
                  : plan.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 18),
            Text(
              '${plan.sessionsPerWeek} sessions / week   •   ${plan.minutes} min',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => showWorkoutSheet(
                  context,
                  ref,
                  uid,
                  type: plan.name,
                  minutes: plan.minutes,
                ),
                child: const Text('Start session'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Recommendation extends StatelessWidget {
  const _Recommendation({
    required this.title,
    required this.detail,
    required this.icon,
    this.onTap,
  });
  final String title, detail;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 250,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xff303636)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _lime),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(detail, style: const TextStyle(color: _muted, fontSize: 13)),
        ],
      ),
    ),
    ),
  );
}

class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key, required this.user});
  final User user;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workouts = ref.watch(workoutsProvider(user.uid));
    final profile = ref.watch(profileProvider(user.uid));
    return PageLayout(
      title: 'Insights',
      subtitle: 'A clearer picture of the consistency you are building.',
      action: IconButton.filledTonal(
        onPressed: FirebaseAuth.instance.signOut,
        icon: const Icon(Icons.logout_outlined),
      ),
      child: workouts.when(
        loading: () => const _LoadingPanel(),
        error: (error, _) => _DataError(error: error),
        data: (all) {
          final goal = profile.maybeWhen(
            data: (data) => (data['weekly_goal'] as num?)?.toInt() ?? 4,
            orElse: () => 4,
          );
          final calorieGoal = profile.maybeWhen(
            data: (data) =>
                (data['weekly_calorie_goal'] as num?)?.toInt() ?? 2000,
            orElse: () => 2000,
          );
          final week = _thisWeek(all);
          final totalMinutes = all.fold(
            0,
            (total, workout) => total + workout.duration,
          );
          final totalCalories = all.fold(
            0,
            (total, workout) => total + workout.calories,
          );
          final favourite = _favouriteActivity(all);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 27,
                        backgroundColor: _lime,
                        foregroundColor: _ink,
                        child: Text(
                          (user.email ?? 'P').substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 21,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.email ?? 'Pulse member',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Personal training workspace',
                              style: TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _changeGoal(context, ref, user.uid, goal),
                        child: const Text('Edit goal'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              AcwrCard(workouts: all),
              const SizedBox(height: 22),
              Text(
                'This week',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 86,
                        height: 86,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: goal == 0
                                  ? 0
                                  : math.min(1, week.length / goal),
                              strokeWidth: 9,
                              backgroundColor: _surfaceSoft,
                              color: _lime,
                            ),
                            Center(
                              child: Text(
                                '${week.length}/$goal',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Session goal',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Your weekly target keeps your training rhythm visible.',
                              style: TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _TrendCard(
                analysis: _analyseTrend(all, calorieGoal),
                onEditTarget: () =>
                    _changeCalorieGoal(context, ref, user.uid, calorieGoal),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _InsightTile(
                    label: 'All-time sessions',
                    value: '${all.length}',
                    icon: Icons.check_circle_outline,
                  ),
                  _InsightTile(
                    label: 'Total active minutes',
                    value: _number(totalMinutes),
                    icon: Icons.timer_outlined,
                  ),
                  _InsightTile(
                    label: 'Energy recorded',
                    value: '${_number(totalCalories)} kcal',
                    icon: Icons.local_fire_department_outlined,
                  ),
                  _InsightTile(
                    label: 'Most logged',
                    value: favourite,
                    icon: Icons.star_outline,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.analysis, required this.onEditTarget});
  final TrendAnalysis analysis;
  final VoidCallback onEditTarget;

  @override
  Widget build(BuildContext context) {
    final gap = (analysis.weeklyTarget - analysis.projectedWeeklyCalories)
        .abs();
    final directionWord = analysis.direction == 'rising'
        ? 'upward'
        : analysis.direction == 'easing'
        ? 'easing'
        : 'steady';
    final explanation = analysis.onTrack
        ? 'At your current $directionWord rate, you are on track to reach about ${_number(analysis.projectedWeeklyCalories)} kcal this week.'
        : 'At your current rate, you are projected to reach about ${_number(analysis.projectedWeeklyCalories)} kcal — ${_number(gap)} kcal short of target.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: (analysis.onTrack ? _lime : const Color(0xffFFB86B))
                    .withValues(alpha: .14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                analysis.onTrack
                    ? Icons.trending_up_rounded
                    : Icons.trending_flat_rounded,
                color: analysis.onTrack ? _lime : const Color(0xffFFB86B),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Weekly trend forecast',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                        onPressed: onEditTarget,
                        child: Text('Target ${_number(analysis.weeklyTarget)}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(explanation, style: const TextStyle(color: _muted)),
                  const SizedBox(height: 11),
                  Text(
                    'Based on a linear regression of your last 56 days of daily activity.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 245,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _lime),
            const SizedBox(height: 20),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: _muted, fontSize: 13)),
          ],
        ),
      ),
    ),
  );
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 300,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _DataError extends StatelessWidget {
  const _DataError({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 38, color: _lime),
          const SizedBox(height: 12),
          const Text(
            'We could not load your fitness data.',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
        ],
      ),
    ),
  );
}

Future<void> showWorkoutSheet(
  BuildContext context,
  WidgetRef ref,
  String uid, {
  String type = 'Run',
  int? minutes,
}) async {
  final formKey = GlobalKey<FormState>();
  final duration = TextEditingController(text: minutes?.toString() ?? '');
  final calories = TextEditingController();
  final notes = TextEditingController();
  final naturalLanguage = TextEditingController();
  var selectedType = type;
  var intensity = 'Moderate';
  var date = DateTime.now();
  WorkoutDraft? parsedDraft;
  String? parseMessage;
  var parsing = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          18,
          22,
          22 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xff4A5353),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Log a workout',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Save a session to update your live progress.',
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xff202927),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xff3C4C45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: _lime,
                              size: 19,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Describe it in plain English',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: naturalLanguage,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'e.g. ran 5k in 28 minutes',
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: parsing
                                ? null
                                : () async {
                                    if (naturalLanguage.text.trim().isEmpty) {
                                      setSheetState(
                                        () => parseMessage =
                                            'Describe a workout first.',
                                      );
                                      return;
                                    }
                                    setSheetState(() {
                                      parsing = true;
                                      parseMessage = null;
                                    });
                                    try {
                                      final draft = await ref
                                          .read(workoutParserProvider)
                                          .parse(naturalLanguage.text.trim());
                                      setSheetState(() {
                                        parsedDraft = draft;
                                        selectedType = draft.exerciseType;
                                        duration.text =
                                            '${draft.durationMinutes}';
                                        calories.text =
                                            '${draft.estimatedCalories}';
                                        if (notes.text.isEmpty) {
                                          notes.text = naturalLanguage.text
                                              .trim();
                                        }
                                      });
                                    } on WorkoutParseException catch (error) {
                                      setSheetState(
                                        () => parseMessage = error.message,
                                      );
                                    } finally {
                                      if (context.mounted) {
                                        setSheetState(() => parsing = false);
                                      }
                                    }
                                  },
                            icon: parsing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.auto_fix_high_rounded),
                            label: Text(
                              parsing ? 'Parsing workout...' : 'Parse workout',
                            ),
                          ),
                        ),
                        if (parseMessage != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            parseMessage!,
                            style: const TextStyle(
                              color: Color(0xffFFCC8B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (parsedDraft != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _lime.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.verified_outlined,
                                  color: _lime,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    '${parsedDraft!.exerciseType} · ${parsedDraft!.durationMinutes} min · ${parsedDraft!.estimatedCalories} kcal',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            parsedDraft!.usedMetFallback
                                ? 'Calories use the local MET safety estimate. Review and edit below before saving.'
                                : 'AI estimate ready. Review and edit every value below before saving.',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Structured details',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Activity'),
                    items:
                        const [
                              'Run',
                              'Walk',
                              'Cycle',
                              'Strength',
                              'Yoga',
                              'Swimming',
                              'HIIT',
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setSheetState(() => selectedType = value!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: duration,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minutes',
                          ),
                          validator: (value) =>
                              (int.tryParse(value ?? '') ?? 0) > 0
                              ? null
                              : 'Enter minutes',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: calories,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Calories',
                          ),
                          validator: (value) =>
                              (int.tryParse(value ?? '') ?? 0) > 0
                              ? null
                              : 'Enter calories',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: intensity,
                    decoration: const InputDecoration(labelText: 'Intensity'),
                    items: const ['Easy', 'Moderate', 'High']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => intensity = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notes,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setSheetState(() => date = picked);
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_dateLabel(date)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final workout = Workout(
                          id: '',
                          type: selectedType,
                          duration: int.parse(duration.text),
                          calories: int.parse(calories.text),
                          time: date,
                          notes: notes.text.trim(),
                          intensity: intensity,
                        );
                        final anomaly = await ref
                            .read(repositoryProvider)
                            .anomalyCheck(uid, workout);
                        if (anomaly != null && context.mounted) {
                          final saveAnyway = await _confirmAnomaly(
                            context,
                            anomaly,
                          );
                          if (!saveAnyway) return;
                        }
                        await ref
                            .read(repositoryProvider)
                            .addWorkout(uid, workout);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Save workout'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  duration.dispose();
  calories.dispose();
  notes.dispose();
  naturalLanguage.dispose();
}

Future<void> showPlanSheet(
  BuildContext context,
  WidgetRef ref,
  String uid, {
  String? initialName,
}) async {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: initialName);
  final description = TextEditingController();
  final sessions = TextEditingController(text: '3');
  final minutes = TextEditingController(text: '30');
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        20,
        22,
        22 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create a plan',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Plan name'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Give your plan a name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: description,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What is this plan for?',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: sessions,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Sessions / week',
                        ),
                        validator: (value) =>
                            (int.tryParse(value ?? '') ?? 0) > 0
                            ? null
                            : 'Required',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: minutes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minutes / session',
                        ),
                        validator: (value) =>
                            (int.tryParse(value ?? '') ?? 0) > 0
                            ? null
                            : 'Required',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      await ref
                          .read(repositoryProvider)
                          .addPlan(
                            uid,
                            TrainingPlan(
                              id: '',
                              name: name.text.trim(),
                              description: description.text.trim(),
                              sessionsPerWeek: int.parse(sessions.text),
                              minutes: int.parse(minutes.text),
                            ),
                          );
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Create plan'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  name.dispose();
  description.dispose();
  sessions.dispose();
  minutes.dispose();
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  String uid,
  Workout workout,
) async {
  final delete = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete activity?'),
      content: Text(
        '${workout.type} will be permanently removed from your history.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (delete == true) {
    await ref.read(repositoryProvider).deleteWorkout(uid, workout.id);
  }
}

Future<void> _changeGoal(
  BuildContext context,
  WidgetRef ref,
  String uid,
  int currentGoal,
) async {
  final controller = TextEditingController(text: '$currentGoal');
  final formKey = GlobalKey<FormState>();
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Weekly session goal'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Sessions per week'),
          validator: (value) =>
              (int.tryParse(value ?? '') ?? 0) > 0 &&
                  (int.tryParse(value ?? '') ?? 0) <= 14
              ? null
              : 'Choose 1–14 sessions',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, true);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (save == true) {
    await ref
        .read(repositoryProvider)
        .setWeeklyGoal(uid, int.parse(controller.text));
  }
  controller.dispose();
}

Future<void> _changeCalorieGoal(
  BuildContext context,
  WidgetRef ref,
  String uid,
  int currentGoal,
) async {
  final controller = TextEditingController(text: '$currentGoal');
  final formKey = GlobalKey<FormState>();
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Weekly calorie target'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Calories per week'),
          validator: (value) =>
              (int.tryParse(value ?? '') ?? 0) >= 500 &&
                  (int.tryParse(value ?? '') ?? 0) <= 50000
              ? null
              : 'Choose a target between 500 and 50,000',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, true);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (save == true) {
    await ref
        .read(repositoryProvider)
        .setWeeklyCalorieGoal(uid, int.parse(controller.text));
  }
  controller.dispose();
}

Future<bool> _confirmAnomaly(BuildContext context, AnomalyCheck anomaly) async {
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.info_outline_rounded, color: Color(0xffFFCC8B)),
      title: const Text('Double-check this entry'),
      content: Text(
        'This would make today ${_number(anomaly.proposedDailyCalories)} kcal. '
        'Your rolling daily average is about ${_number(anomaly.usualDailyCalories)} kcal. '
        'It may be correct — please confirm before saving.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Review entry'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save anyway'),
        ),
      ],
    ),
  );
  return save ?? false;
}

TrendAnalysis _analyseTrend(List<Workout> workouts, int weeklyTarget) {
  final today = DateUtils.dateOnly(DateTime.now());
  final firstDay = today.subtract(const Duration(days: 55));
  final totals = <DateTime, int>{
    for (var offset = 0; offset < 56; offset++)
      firstDay.add(Duration(days: offset)): 0,
  };
  for (final workout in workouts) {
    final day = DateUtils.dateOnly(workout.time);
    if (totals.containsKey(day)) totals[day] = totals[day]! + workout.calories;
  }
  final values = totals.values.map((value) => value.toDouble()).toList();
  final meanX = (values.length - 1) / 2;
  final meanY =
      values.fold<double>(0, (total, value) => total + value) / values.length;
  var numerator = 0.0;
  var denominator = 0.0;
  for (var index = 0; index < values.length; index++) {
    final xDelta = index - meanX;
    numerator += xDelta * (values[index] - meanY);
    denominator += xDelta * xDelta;
  }
  final slope = denominator == 0 ? 0.0 : numerator / denominator;
  final intercept = meanY - slope * meanX;
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  var projection = 0.0;
  for (var offset = 0; offset < 7; offset++) {
    final day = weekStart.add(Duration(days: offset));
    if (!day.isAfter(today)) {
      projection += (totals[day] ?? 0).toDouble();
    } else {
      final x = day.difference(firstDay).inDays;
      projection += math.max(0, intercept + slope * x);
    }
  }
  return TrendAnalysis(
    slope: slope,
    projectedWeeklyCalories: projection.round(),
    weeklyTarget: weeklyTarget,
  );
}

List<Workout> _thisWeek(List<Workout> workouts) {
  final now = DateTime.now();
  final start = DateUtils.dateOnly(
    now,
  ).subtract(Duration(days: now.weekday - 1));
  return workouts
      .where((workout) => !DateUtils.dateOnly(workout.time).isBefore(start))
      .toList();
}

int _streak(List<Workout> workouts) {
  final days = workouts
      .map((workout) => DateUtils.dateOnly(workout.time))
      .toSet();
  var date = DateUtils.dateOnly(DateTime.now());
  if (!days.contains(date)) date = date.subtract(const Duration(days: 1));
  var streak = 0;
  while (days.contains(date)) {
    streak++;
    date = date.subtract(const Duration(days: 1));
  }
  return streak;
}

String _favouriteActivity(List<Workout> workouts) {
  if (workouts.isEmpty) return '—';
  final counts = <String, int>{};
  for (final workout in workouts) {
    counts[workout.type] = (counts[workout.type] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

String _number(int value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k'
    : '$value';
String _formatSeconds(int total) {
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _greeting(User user) {
  final hour = DateTime.now().hour;
  final phrase = hour < 12
      ? 'Good morning'
      : hour < 18
      ? 'Good afternoon'
      : 'Good evening';
  final name = user.displayName?.split(' ').first ?? '';
  return '$phrase${name.isEmpty ? '' : ', $name'}';
}

String _dateLabel(DateTime date) {
  if (DateUtils.isSameDay(date, DateTime.now())) return 'Today';
  if (DateUtils.isSameDay(
    date,
    DateTime.now().subtract(const Duration(days: 1)),
  )) {
    return 'Yesterday';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

IconData _activityIcon(String type) {
  final value = type.toLowerCase();
  if (value.contains('run')) return Icons.directions_run_rounded;
  if (value.contains('cycle') || value.contains('bike')) {
    return Icons.directions_bike_rounded;
  }
  if (value.contains('strength')) return Icons.fitness_center_rounded;
  if (value.contains('yoga')) return Icons.self_improvement_rounded;
  if (value.contains('walk')) return Icons.directions_walk_rounded;
  return Icons.bolt_rounded;
}

Color _activityColor(String type) {
  final value = type.toLowerCase();
  if (value.contains('run')) return const Color(0xffFFB86B);
  if (value.contains('cycle')) return const Color(0xff77C8FF);
  if (value.contains('strength')) return const Color(0xffE6A4FF);
  return _lime;
}
