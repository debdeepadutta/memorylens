class ContextClassificationService {
  static const Map<String, List<String>> _categoryKeywords = {
    'Study': [
      'exam',
      'quiz',
      'result',
      'marks',
      'university',
      'college',
      'physics',
      'math',
      'science',
      'study',
      'homework',
      'lecture',
      'notes',
      'assignment',
      'textbook',
      'syllabus',
      'course',
      'handwriting',
      'classroom',
    ],
    'Finance': [
      'invoice',
      'receipt',
      'paid',
      'total',
      'balance',
      'amount',
      'bill',
      'transaction',
      'debit',
      'credit',
      'bank',
      'statement',
      'tax',
      'gst',
      'payment',
      'refno',
      'cash',
      'checkout',
      'merchant',
    ],
    'Travel': [
      'boarding',
      'flight',
      'seat',
      'ticket',
      'hotel',
      'booking',
      'passport',
      'visa',
      'departure',
      'arrival',
      'terminal',
      'gate',
      'itinerary',
      'resort',
      'destination',
      'monument',
      'museum',
      'airport',
      'railway',
      'train',
    ],
    'Work': [
      'meeting',
      'project',
      'deadline',
      'report',
      'presentation',
      'office',
      'slack',
      'zoom',
      'career',
      'job',
      'hiring',
      'resume',
      'cv',
      'contract',
      'company',
      'industry',
      'spreadsheet',
      'agenda',
    ],
    'Shopping': [
      'amazon',
      'flipkart',
      'order',
      'shipping',
      'delivery',
      'price',
      'discount',
      'grocery',
      'supermarket',
      'cart',
      'buy',
      'purchased',
      'store',
      'sale',
      'outfit',
      'brand',
    ],
    'Health': [
      'doctor',
      'hospital',
      'prescription',
      'medicine',
      'pharmacy',
      'diet',
      'workout',
      'health',
      'fitness',
      'patient',
      'clinic',
      'diagnosis',
      'dosage',
      'vitamin',
      'vaccine',
    ],
    'Social': [
      'birthday',
      'party',
      'wedding',
      'dinner',
      'lunch',
      'outing',
      'hangout',
      'celebration',
      'gathering',
      'festival',
      'invite',
      'treat',
      'restaurant',
    ],
  };

  static const Map<String, List<String>> _categoryLabels = {
    'Study': [
      'Book',
      'Paper',
      'Document',
      'Handwriting',
      'Stationery',
      'Textbook',
    ],
    'Finance': ['Invoice', 'Receipt', 'Menu', 'Paperwork'],
    'Travel': [
      'Airport',
      'Aircraft',
      'Passport',
      'Map',
      'Tourist attraction',
      'Backpack',
      'Luggage',
    ],
    'Work': ['Office', 'Computer', 'Meeting room', 'Whiteboard', 'Desk'],
    'Shopping': [
      'Clothing',
      'Product',
      'Shopping bag',
      'Footwear',
      'Consumer electronics',
    ],
    'Health': ['Medicine', 'Medical equipment', 'Stethoscope', 'Fitness'],
    'Social': [
      'People',
      'Group of people',
      'Restaurant',
      'Alcoholic beverage',
      'Food',
      'Event',
    ],
  };

  static String classify(String text, String labels, {String? location}) {
    final lowerText = text.toLowerCase();
    final lowerLabels = labels.toLowerCase();

    Map<String, int> scores = {
      'Study': 0,
      'Finance': 0,
      'Travel': 0,
      'Work': 0,
      'Shopping': 0,
      'Health': 0,
      'Social': 0,
    };

    // Keyword matching
    _categoryKeywords.forEach((category, keywords) {
      for (var kw in keywords) {
        if (lowerText.contains(kw)) scores[category] = scores[category]! + 3;
      }
    });

    // Label matching
    _categoryLabels.forEach((category, labelsList) {
      for (var lb in labelsList) {
        if (lowerLabels.contains(lb.toLowerCase()))
          scores[category] = scores[category]! + 5;
      }
    });

    // Location boost
    if (location != null && location.isNotEmpty && !location.contains('Home')) {
      scores['Travel'] = scores['Travel']! + 2;
    }

    // Special exact matches (high confidence)
    if (lowerText.contains('boarding pass') || lowerText.contains('visa info'))
      return 'Travel';
    if (lowerText.contains('income tax') ||
        lowerText.contains('bank statement'))
      return 'Finance';
    if (lowerText.contains('exam schedule') || lowerText.contains('marksheet'))
      return 'Study';

    String bestCategory = 'Personal';
    int maxScore = 5; // Minimum threshold

    scores.forEach((category, score) {
      if (score > maxScore) {
        maxScore = score;
        bestCategory = category;
      }
    });

    return bestCategory;
  }
}
