import 'package:flutter/material.dart';
import 'package:yanji/models/meeting.dart';

class MeetingProvider with ChangeNotifier {
  List<Meeting> _meetings = [];
  
  List<Meeting> get meetings => _meetings;
  
  void addMeeting(Meeting meeting) {
    _meetings.add(meeting);
    notifyListeners();
  }
  
  void removeMeeting(int id) {
    _meetings.removeWhere((meeting) => meeting.id == id);
    notifyListeners();
  }
}