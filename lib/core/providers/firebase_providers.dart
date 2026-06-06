import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_refs.dart';

final firebaseRefsProvider = Provider<FirebaseRefs>((ref) => FirebaseRefs());
