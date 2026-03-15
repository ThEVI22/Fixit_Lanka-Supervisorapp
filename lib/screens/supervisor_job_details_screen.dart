import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart'; // ✅ Location Validation
import '../widgets/custom_dialog.dart';

class SupervisorJobDetailsScreen extends StatefulWidget {
  const SupervisorJobDetailsScreen({super.key});
  @override
  State<SupervisorJobDetailsScreen> createState() => _SupervisorJobDetailsScreenState();
}

class _SupervisorJobDetailsScreenState extends State<SupervisorJobDetailsScreen> {
  String? _id; 
  Map<String, dynamic>? _data; 
  List<Map<String, dynamic>> _crew = []; 
  List<QueryDocumentSnapshot> _assignedStaff = []; // ✅ Track assigned staff docs
  bool _loading = true;
  bool _actionLoading = false; 

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _id = ModalRoute.of(context)?.settings.arguments as String?;
    if (_id != null) _fetch();
  }

  Future<void> _fetch() async {
    final report = await FirebaseFirestore.instance.collection('all_reports').doc(_id).get();
    
    // 1. Fetch workers ALREADY in this Report (Active Sources)
    final teamStaff = await FirebaseFirestore.instance
        .collection('staff')
        .where('currentReportId', isEqualTo: _id)
        .get();

    // 2. Fetch AVAILABLE workers (Global Pool)
    final poolStaff = await FirebaseFirestore.instance
        .collection('staff')
        .where('status', isEqualTo: 'Available')
        .where('role', isEqualTo: 'Worker')
        .get();

    if (mounted) setState(() { 
      _data = report.data(); 
      _assignedStaff = teamStaff.docs; // ✅ Store for UI
      
      String rCat = (_data?['category'] ?? "").toString().toLowerCase();
      
      // Merge & Deduplicate for Logic (Start Job pool)
      final Map<String, Map<String, dynamic>> uniqueWorkers = {};

      for (var d in teamStaff.docs) {
        uniqueWorkers[d.id] = {...d.data(), 'docId': d.id};
      }
      for (var d in poolStaff.docs) {
        uniqueWorkers[d.id] = {...d.data(), 'docId': d.id};
      }

      _crew = uniqueWorkers.values
          .where((w) {
            String wSpec = (w['specialization'] ?? "").toString().toLowerCase();
            return wSpec.contains(rCat) || rCat.contains(wSpec);
          })
          .toList();
      
      _loading = false; 
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: Colors.white, body: Center(child: CircularProgressIndicator(color: Colors.black)));
    
    String s = _data?['status'] ?? "";
    bool started = _data?.containsKey('startedAt') ?? false;

    // Determine Status Color & Label
    Color statusColor = Colors.blue; 
    Color statusBg = Colors.blue.withOpacity(0.1);
    if (s == 'Resolved') { statusColor = Colors.green; statusBg = Colors.green.withOpacity(0.1); }
    else if (s == 'On-Hold') { statusColor = Colors.orange; statusBg = Colors.orange.withOpacity(0.1); }
    else if (started) { statusColor = const Color(0xFF2962FF); statusBg = const Color(0xFFE3F2FD); } // Active blue
    else { statusColor = Colors.black; statusBg = Colors.grey[100]!; }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, 
        centerTitle: true,
        title: Text("Execution Management", style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)), 
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20), 
          onPressed: () => Navigator.pop(context)
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          
          // IMAGE SECTION
          Container(
            height: 220, width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[100], 
              borderRadius: BorderRadius.circular(24),
              image: (_data?['photos'] != null && (_data!['photos'] as List).isNotEmpty)
                ? DecorationImage(image: NetworkImage(_data!['photos'][0]), fit: BoxFit.cover)
                : null
            ),
            child: _data?['photos'] == null || (_data!['photos'] as List).isEmpty 
              ? const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 40)) 
              : null
          ),

          const SizedBox(height: 24),

          // ID & STATUS ROW
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                child: Text(_data?['adminReportId'] ?? "ID", style: GoogleFonts.robotoMono(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)), // Pill shape
                child: Text(s.isEmpty ? "Unknown" : s, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: statusColor)),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // TITLE
          Text(_data?['category'] ?? "Task", style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.black)),
          
          const SizedBox(height: 12),

          // LOCATION
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_rounded, color: Color(0xFFFF3D00), size: 20), // Red pin
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _data?['locationName'] ?? "No location detected", 
                  style: GoogleFonts.outfit(color: Colors.grey[500], fontWeight: FontWeight.w500, fontSize: 14, height: 1.4)
                )
              )
            ]
          ),

          const SizedBox(height: 32),

          // PERSONNEL ASSIGNED
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Personnel Assigned", style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black)),
              if (s != 'Resolved' && started) // Only show Add if active
                InkWell(
                  onTap: _showAddWorker,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text("+ Add Member", style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                  ),
                )
            ],
          ),
          const SizedBox(height: 12),
          
          if (_assignedStaff.isNotEmpty) ...[
            Column(
              children: _assignedStaff.take(3).map<Widget>((doc) => _buildWorkerCard(doc, s, started)).toList(),
            ),
            if (_assignedStaff.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                   width: double.infinity,
                   child: OutlinedButton(
                     onPressed: _showAllWorkers,
                     style: OutlinedButton.styleFrom(
                       foregroundColor: Colors.black,
                       side: BorderSide(color: Colors.grey[300]!),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                       padding: const EdgeInsets.symmetric(vertical: 12)
                     ),
                     child: Text("View All (+${_assignedStaff.length - 3})", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                   ),
                ),
              )
          ]
          else 
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
              child: Column(
                children: [
                   (s == 'Resolved' ? Icon(Icons.task_alt_rounded, size: 32, color: Colors.green[300]) : Icon(Icons.groups_3_outlined, size: 32, color: Colors.grey[300])),
                  const SizedBox(height: 12),
                   (s == 'Resolved' ? Text("Job Completed", style: GoogleFonts.outfit(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 14)) : Text("No crew assigned yet", style: GoogleFonts.outfit(color: Colors.grey[500], fontWeight: FontWeight.bold, fontSize: 14))),
                   (s == 'Resolved' ? Text("Field crew has been released from this task.", style: GoogleFonts.outfit(color: Colors.green[600], fontWeight: FontWeight.normal, fontSize: 12)) : Text("Add members to start the job", style: GoogleFonts.outfit(color: Colors.grey[400], fontWeight: FontWeight.normal, fontSize: 12))),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // JOB DESCRIPTION
          Text("Job Description", style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black)),
          const SizedBox(height: 8),
          Text(
            _data?['description'] ?? "No description provided.", 
            style: GoogleFonts.outfit(color: Colors.grey[600], height: 1.6, fontSize: 14, fontWeight: FontWeight.w400)
          ),

          const SizedBox(height: 120), // Bottom padding
        ]),
      ),
      extendBody: true, 
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(24), 
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 40, offset: const Offset(0, -10))]
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_actionLoading) const LinearProgressIndicator(color: Colors.black, backgroundColor: Colors.grey),
            if (_actionLoading) const SizedBox(height: 10),
            Row(children: [
              _dirBtn(), const SizedBox(width: 16),
              Expanded(child: _logicBtn(s, started)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _dirBtn() => Container(
    height: 54, width: 54, 
    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16)), 
    child: IconButton(icon: const Icon(Icons.directions_rounded, color: Colors.black, size: 26), onPressed: () async {
    double? lat = _data?['lat'];
    double? lng = _data?['lng'];

    // Fallback for GeoPoint format
    if (lat == null || lng == null) {
       final loc = _data?['location']; 
       if (loc != null) {
          lat = loc.latitude;
          lng = loc.longitude;
       }
    }

    if (lat == null || lng == null) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No location data available.")));
      return;
    }
    final Uri geoUri = Uri.parse("geo:$lat,$lng?q=$lat,$lng");
    final Uri webUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");

    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error launching map: $e")));
    }
  }));

  Widget _logicBtn(String s, bool started) {
    if (s == 'Resolved') return _actionBtn("JOB COMPLETED", Colors.grey[200]!, Colors.black, () {}, outlined: false);

    // 1. Fresh Job -> Start
    if (!started && s != 'On-Hold') return _actionBtn("START JOB", Colors.black, Colors.white, _showStart);

    // 2. On Hold -> Resume
    if (s == 'On-Hold') return _actionBtn("RESUME JOB", Colors.black, Colors.white, _resumeJob);
    
    // 3. In Progress -> Hold / Complete
    return Row(children: [
      Container(
        height: 54, width: 54, 
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100], // Reverted yellow
          borderRadius: BorderRadius.circular(16)
        ), 
        child: IconButton(
          icon: const Icon(Icons.pause_circle_outline_rounded, color: Colors.black, size: 28), // Improved icon
          onPressed: _showHold,
          tooltip: "Hold Job",
        )
      ),
      Expanded(child: _actionBtn("COMPLETE JOB", Colors.black, Colors.white, _complete)),
    ]);
  }

  Widget _actionBtn(String t, Color bg, Color fg, VoidCallback o, {bool outlined = false}) => SizedBox(
    width: double.infinity, 
    child: ElevatedButton(
      onPressed: _actionLoading ? null : o, 
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, 
        foregroundColor: fg, 
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shadowColor: Colors.transparent,
        side: outlined ? const BorderSide(color: Colors.black, width: 1.5) : BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
      ), 
      child: Text(t, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16))
    )
  );

  // --- NOTIFICATIONS ---

  Future<void> _notifyAdmin(String action, String title, String body) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'target': 'admin', // Key for admin sidebar to listen to
        'type': 'admin_alert',
        'action': action, // start, hold, resume, complete
        'reportId': _id,
        'title': title,
        'body': body,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'teamId': _data?['assignedTeamId'] ?? ""
      });
    } catch (e) {
      print("Error sending admin notification: $e");
    }
  }

  Future<void> _notifyUser(String title, String body) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'target': 'user',
        'type': 'status_update',
        'reportId': _id,
        'title': title,
        'message': body, // User app uses 'message' key
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'userId': _data?['userId'] ?? "" // Helpful for direct targeting if needed later
      });
    } catch (e) {
      print("Error sending user notification: $e");
    }
  }

  // ✅ NEW: Notify Project Workers
  // ✅ Notify Project Workers (Robust: Doc ID + Staff ID)
  Future<void> _notifyWorkers(String title, String message, {String type = 'info'}) async {
    // Notify all assigned staff
    for (var doc in _assignedStaff) {
      final data = doc.data() as Map<String, dynamic>;
      final workerId = data['staffId'] as String?;
      final workerDocId = doc.id;
      await _sendSingleWorkerNotification(workerDocId, workerId, type, title, message);
    }
  }

  // ✅ Send Notification to Single Worker (Single Target to avoid Duplicates)
  Future<void> _sendSingleWorkerNotification(String docId, String? staffId, String type, String title, String message) async {
      // Prioritize Doc ID (Most Robust), fallback to Staff ID
      final String target = (docId.isNotEmpty) ? docId : (staffId ?? "");
      
      if (target.isEmpty) return; // Should not happen in valid flow

      await FirebaseFirestore.instance.collection('notifications').add({
        'target': target,
        'type': type,
        'title': title,
        'message': message,
        'reportId': _id,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'metadata': {'workerId': staffId, 'docId': docId}
      });
  }

  // --- ACTIONS ---

  void _resumeJob() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CustomDialog(
        icon: Icons.play_arrow_rounded,
        title: "Resume Job?",
        subtitle: "This will mark the job as 'In-Progress' again.",
        primaryActionText: "Resume",
        onPrimaryAction: () async {
          Navigator.pop(context);
          setState(() => _actionLoading = true);
          await FirebaseFirestore.instance.collection('all_reports').doc(_id).update({'status': 'In-progress'});
          await _notifyAdmin('resume', 'Job Resumed', 'Supervisor has resumed job: ${_data?['category'] ?? "Task"}');
          await _notifyUser('Work Resumed', 'The crew has resumed work on your report.');
          await _notifyWorkers('Job Resumed', 'Supervisor resumed the job. You can clock in again.', type: 'info'); // ✅ Notify Workers
          setState(() => _actionLoading = false);
          _fetch();
          if(mounted) _showSuccess("Job Resumed", "Work status set to In-Progress.");
        },
      )
    );
  }

  // ... (keeping _showSuccess) ...
  
  void _showSuccess(String title, String body) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CustomDialog(
        icon: Icons.check_circle_rounded,
        iconColor: Colors.green,
        iconContainerColor: Colors.green.withOpacity(0.1),
        title: title,
        subtitle: body,
        primaryActionText: "Continue",
        secondaryActionText: "",
        onPrimaryAction: () => Navigator.pop(ctx),
      )
    );
  }

  void _showStart() {
    // ... (rest of _showStart up to loop)
    DateTime est = DateTime.now().add(const Duration(days: 1)); 
    List<String> selIds = [];
    List<String> selNames = [];

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => StatefulBuilder(builder: (c, st) => Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         // ... (UI Code same as before) ...
         Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
         const SizedBox(height: 24),
         Text("Initialize Job", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
         const SizedBox(height: 32),
         
        // Date Picker
        Text("ESTIMATED COMPLETION", style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey[400], letterSpacing: 1)),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: est, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
            if (d != null) st(() => est = d);
          },
          child: Container(
            padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.calendar_today_rounded, size: 20), const SizedBox(width: 12),
              Text(DateFormat('MMMM d, yyyy').format(est), style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16))
            ]),
          ),
        ),
        
        const SizedBox(height: 32),
        Text("ASSIGN WORKERS (${selIds.length})", style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey[400], letterSpacing: 1)),
        const SizedBox(height: 12),
        
         // ... (Worker List Code same as before) ...
        Expanded(child: _crew.isEmpty 
          ? Center(child: Text("No workers available"))
          : ListView.separated(
          itemCount: _crew.length,
          separatorBuilder: (_,__) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) {
            final w = _crew[i];
            bool isSel = selIds.contains(w['docId']);
            return InkWell(
              onTap: () => st(() { if(isSel) { selIds.remove(w['docId']); selNames.remove(w['fullName']); } else { selIds.add(w['docId']); selNames.add(w['fullName']); } }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: isSel ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isSel ? Colors.black : Colors.grey[200]!)),
                child: Row(children: [
                   CircleAvatar(backgroundColor: isSel ? Colors.white : Colors.grey[100], radius: 14, child: Text(w['fullName'][0], style: GoogleFonts.outfit(color: isSel ? Colors.black : Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 12))),
                   const SizedBox(width: 12),
                   Text(w['fullName'], style: GoogleFonts.outfit(color: isSel ? Colors.white : Colors.black, fontWeight: FontWeight.w600, fontSize: 16)),
                   const Spacer(),
                   if(isSel) const Icon(Icons.check_circle, color: Colors.white, size: 20)
                ]),
              ),
            );
          },
        )),


        const SizedBox(height: 20),
        SizedBox(height: 56, width: double.infinity, child: ElevatedButton(
          onPressed: selIds.isEmpty ? null : () async {
            Navigator.pop(context);
            setState(() => _actionLoading = true);
            
            // 1. Update Report
            await FirebaseFirestore.instance.collection('all_reports').doc(_id).update({
              'status': 'In-progress', 
              'startedAt': DateTime.now().millisecondsSinceEpoch, 
              'estimatedDate': Timestamp.fromDate(est),
              'workers': selNames,
              'workerIds': selIds 
            });
            
            final prefs = await SharedPreferences.getInstance();
            final tid = prefs.getString('team_id') ?? "";

            // 2. Notify Workers & Update Status
            final batch = FirebaseFirestore.instance.batch();
            for (String uid in selIds) {
              // Lookup Staff ID if available in _crew
              String? sId;
              try {
                final wData = _crew.firstWhere((element) => element['docId'] == uid, orElse: () => {});
                sId = wData['staffId'];
              } catch (_) {}

              await _sendSingleWorkerNotification(uid, sId, 'assignment', 'New Job Assignment', 'You have been assigned to: ${_data?['category'] ?? "Task"}');

              // ✅ Update Status to In-Work
              final workerRef = FirebaseFirestore.instance.collection('staff').doc(uid);
              batch.update(workerRef, {
                'status': 'In-Work', 
                'currentTeamId': tid,
                'currentReportId': _id
              });
            }
            await batch.commit();

            // 3. Notify Admin & User
            await _notifyAdmin('start', 'Job Started', 'Supervisor has started work on: ${_data?['category'] ?? "Task"}');
            await _notifyUser('Work Started', 'Work has started on your report.'); // Notify User

            setState(() => _actionLoading = false);
            _fetch();
            if(mounted) _showSuccess("Job Started", "Crew deployed & notifications sent.");
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: Text("Deploy Crew", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
        ))
      ]),
    )));
  }

  void _showHold() {
    String? selectedReason;
    final tc = TextEditingController();
    final reasons = ["Materials Unavailable", "Weather Conditions", "Site Inaccessible", "Safety Hazard", "Worker Unavailable", "Permit/Approval Pending"];

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true,
      backgroundColor: Colors.transparent, 
      builder: (ctx) => StatefulBuilder(builder: (c, st) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
             const SizedBox(height: 24),
             Text("Suspend Job", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
             const SizedBox(height: 8),
             Text("Select a reason for putting this job on hold.", style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey[500])),
             const SizedBox(height: 24),
             
             // Styled Reason List
             SizedBox(
              height: 320,
              child: ListView(
                 children: [
                    ...reasons.map((r) {
                      bool isSelected = selectedReason == r;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () => st(() => selectedReason = r),
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.black : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isSelected ? Colors.black : Colors.grey[200]!)
                            ),
                            child: Row(
                              children: [
                                Expanded(child: Text(r, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: isSelected ? Colors.white : Colors.black))),
                                if (isSelected) const Icon(Icons.check_circle, color: Colors.white, size: 20)
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    
                    // "Other" Option
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => st(() => selectedReason = "Other"),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: selectedReason == "Other" ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: selectedReason == "Other" ? Colors.black : Colors.grey[200]!)
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text("Other", style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: selectedReason == "Other" ? Colors.white : Colors.black))),
                              if (selectedReason == "Other") const Icon(Icons.check_circle, color: Colors.white, size: 20)
                            ],
                          ),
                        ),
                      ),
                    ),

                    if(selectedReason == "Other") 
                      TextField(
                        controller: tc, 
                        decoration: InputDecoration(
                          hintText: "Enter specific reason...",
                          hintStyle: GoogleFonts.outfit(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[50], 
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)
                        )
                      )
                 ]
              )
             ),

             const SizedBox(height: 24),
             Row(children: [
               Expanded(
                 child: OutlinedButton(
                   onPressed: () => Navigator.pop(context), 
                   style: OutlinedButton.styleFrom(
                     padding: const EdgeInsets.symmetric(vertical: 16),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                     side: BorderSide(color: Colors.grey[300]!)
                   ),
                   child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.w600))
                 )
               ),
               const SizedBox(width: 16),
               Expanded(
                 child: ElevatedButton(
                   onPressed: selectedReason == null ? null : () async {
                     String finalReason = selectedReason == "Other" ? tc.text : selectedReason!;
                     if (finalReason.trim().isEmpty) return;
               
                     Navigator.pop(context);
                     setState(() => _actionLoading = true);
                     await FirebaseFirestore.instance.collection('all_reports').doc(_id).update({'status': 'On-Hold', 'holdReason': finalReason});
                     await _notifyAdmin('hold', 'Job On Hold', 'Job suspended for: $finalReason');
                     await _notifyUser('Work On Hold', 'Your report is on hold: $finalReason'); 
                     await _notifyWorkers('Job Paused', 'Job placed on hold: $finalReason', type: 'alert'); 
                     setState(() => _actionLoading = false);
                     _fetch();
                     if(mounted) _showSuccess("Job Suspended", "Status updated to On-Hold.");
                   },
                   style: ElevatedButton.styleFrom(
                     backgroundColor: Colors.black,
                     foregroundColor: Colors.white,
                     padding: const EdgeInsets.symmetric(vertical: 16),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                     elevation: 0
                   ),
                   child: Text("Confirm Hold", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                 ),
               ),
             ])
          ],
        ),
      ))
    );
  }

  void _showReplaceWorker(String oldUid, String oldName) {
    String? selectedReason;
    final tc = TextEditingController();
    final reasons = ["Sickness / Medical", "Family Emergency", "Injury On Site", "Performance Issue", "Reassigned"];
    
    // Filter available crew (excluding current assigned)
    final currentIds = _assignedStaff.map((d) => d.id).toSet();
    final availableCrew = _crew.where((w) => !currentIds.contains(w['docId'])).toList();

    if (availableCrew.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No replacements available in the pool.")));
      return;
    }

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (c, st) {
        
        // Listen to text changes for "Other"
        tc.addListener(() {
          if (selectedReason == "Other") st(() {});
        });

        // Validation Helper
        bool isValid() {
          if (selectedReason == null) return false;
          if (selectedReason == "Other" && tc.text.trim().isEmpty) return false;
          return true;
        }

        return Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 30),
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
               const SizedBox(height: 24),
               Text("Replace $oldName", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
               const SizedBox(height: 8),
               Text("Step 1: Select ID/Reason for replacement.", style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 14)),
               const SizedBox(height: 16),

               // Reason Selector
               Container(
                 height: 180,
                 decoration: BoxDecoration(border: Border.all(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(12)),
                 child: ListView(
                   children: [
                     ...reasons.map((r) => RadioListTile<String>(
                        title: Text(r, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500)),
                        value: r, groupValue: selectedReason, activeColor: Colors.black, dense: true,
                        onChanged: (v) => st(() => selectedReason = v),
                      )),
                      RadioListTile<String>(
                        title: Text("Other", style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500)),
                        value: "Other", groupValue: selectedReason, activeColor: Colors.black, dense: true,
                        onChanged: (v) => st(() => selectedReason = v),
                      ),
                      if (selectedReason == "Other")
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: TextField(controller: tc, decoration: const InputDecoration(hintText: "Reason...", isDense: true, border: OutlineInputBorder())),
                        )
                   ],
                 ),
               ),

               const SizedBox(height: 24),
               Text("Step 2: Select Replacement", style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 14)),
               const SizedBox(height: 12),

               Expanded(
                 child: ListView.separated(
                    itemCount: availableCrew.length,
                    separatorBuilder: (_,__) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final w = availableCrew[i];
                      return InkWell(
                        onTap: () {}, // Removed worker selection logic as it conflicts with reason selection
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[200]!)
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(backgroundColor: Colors.grey[100], child: Text(w['fullName'][0], style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(w['fullName'], style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text(w['specialization'] ?? "Worker", style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
                                ])),
                              ElevatedButton(
                                onPressed: !isValid() ? null : () async {
                                   String finalReason = selectedReason == "Other" ? tc.text : selectedReason!;
                                   
                                   Navigator.pop(context);
                                   setState(() => _actionLoading = true);
             
                                   // ✅ ATOMIC SWAP
                                   final batch = FirebaseFirestore.instance.batch();
                                   
                                   // 1. Release Old
                                   final oldRef = FirebaseFirestore.instance.collection('staff').doc(oldUid);
                                   batch.update(oldRef, {'status': 'Available', 'currentReportId': FieldValue.delete(), 'currentTeamId': FieldValue.delete()});
             
                                   // 2. Occupy New
                                   final newRef = FirebaseFirestore.instance.collection('staff').doc(w['docId']);
                                   batch.update(newRef, {'status': 'In-Work', 'currentReportId': _id}); 
             
                                   // 3. Update Report Arrays
                                   final rRef = FirebaseFirestore.instance.collection('all_reports').doc(_id);
                                   batch.update(rRef, {
                                     'workers': FieldValue.arrayRemove([oldName]),
                                     'workerIds': FieldValue.arrayRemove([oldUid])
                                   });
                                   batch.update(rRef, {
                                     'workers': FieldValue.arrayUnion([w['fullName']]),
                                     'workerIds': FieldValue.arrayUnion([w['docId']])
                                   });
             
                                   await batch.commit();
                                   
                                   // 4. Notifications
                                   await _notifyAdmin('worker_replaced', 'Worker Replaced', 'Replaced $oldName with ${w['fullName']}. Reason: $finalReason');
                                   
                                   // Notify OLD Worker (Find Staff ID if possible, otherwise just DocID)
                                   String? oldStaffId;
                                   try {
                                      final oldDoc = _assignedStaff.firstWhere((d) => d.id == oldUid);
                                      oldStaffId = (oldDoc.data() as Map<String, dynamic>)['staffId'];
                                   } catch(_) {}
                                   
                                   await _sendSingleWorkerNotification(oldUid, oldStaffId, 'worker_replaced', 'Removed from Job', 'From this work (${_data?['category'] ?? "Task"}) you have been replaced with ${w['fullName']}. Reason: $finalReason');

                                   // Notify NEW Worker
                                   await _sendSingleWorkerNotification(w['docId'], w['staffId'], 'assignment', 'New Job Assignment', 'You have been assigned to replace $oldName on: ${_data?['category'] ?? "Task"}');

                                   // Notify REMAINING Team (Bystanders)
                                   for (var doc in _assignedStaff) {
                                      if (doc.id == oldUid) continue; // Don't notify the one leaving (already notified)
                                      final d = doc.data() as Map<String, dynamic>;
                                      await _sendSingleWorkerNotification(doc.id, d['staffId'], 'team_update', 'Team Update', '$oldName was replaced by ${w['fullName']}.');
                                   }

                                   setState(() => _actionLoading = false);
                                   _fetch();
                                   if(mounted) _showSuccess("Worker Replaced", "Successfully swapped $oldName with ${w['fullName']}.");
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: const StadiumBorder()),
                                child: const Text("Select"),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                 ),
               )
            ],
          ),
        );
      }),
    );
  }

  void _showRemoveWorker(String uid, String name) {
    // ✅ Validation: Cannot remove the last worker
    if (_assignedStaff.length <= 1) {
      showDialog(
        context: context,
        builder: (ctx) => CustomDialog(
          icon: Icons.error_outline_rounded,
          iconColor: Colors.red,
          iconContainerColor: Colors.red.withOpacity(0.1),
          title: "Cannot Remove Worker",
          subtitle: "You cannot remove the only worker assigned to this job. Assign another worker first or complete the job.",
          primaryActionText: "OK",
          onPrimaryAction: () => Navigator.pop(ctx),
        )
      );
      return;
    }

    String? selectedReason;
    final tc = TextEditingController();
    final reasons = ["Sickness / Medical", "Family Emergency", "Injury On Site", "Performance Issue", "Reassigned"];

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true,
      backgroundColor: Colors.transparent, 
      builder: (ctx) => StatefulBuilder(builder: (c, st) {
        
        // Listen to text changes for "Other"
        tc.addListener(() {
          if (selectedReason == "Other") st(() {});
        });

        // Validation Helper
        bool isValid() {
          if (selectedReason == null) return false;
          if (selectedReason == "Other" && tc.text.trim().isEmpty) return false;
          return true;
        }

        return Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 24),
            Text("Remove $name?", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 8),
            Text("Select a reason for removing this worker.", style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 14)),
            const SizedBox(height: 24),
            
            ...reasons.map((r) => RadioListTile<String>(
              title: Text(r, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w500)),
              value: r, groupValue: selectedReason, activeColor: Colors.black, contentPadding: EdgeInsets.zero,
              onChanged: (v) => st(() => selectedReason = v),
            )),
            
            RadioListTile<String>(
              title: Text("Other", style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w500)),
              value: "Other", groupValue: selectedReason, activeColor: Colors.black, contentPadding: EdgeInsets.zero,
              onChanged: (v) => st(() => selectedReason = v),
            ),

            if (selectedReason == "Other") 
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextField(
                  controller: tc,
                  decoration: InputDecoration(
                    hintText: "Enter specific reason...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                  ),
                ),
              ),

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                onPressed: !isValid() ? null : () async {
                  String finalReason = selectedReason == "Other" ? tc.text : selectedReason!;
                  
                  Navigator.pop(context);
                  setState(() => _actionLoading = true);
                  
                  // LOGIC: Remove Worker
                  await FirebaseFirestore.instance.collection('staff').doc(uid).update({
                    'status': 'Available',
                    'currentReportId': FieldValue.delete(),
                    'currentTeamId': FieldValue.delete()
                  });
                  
                  await FirebaseFirestore.instance.collection('all_reports').doc(_id).update({
                    'workers': FieldValue.arrayRemove([name]),
                    'workerIds': FieldValue.arrayRemove([uid])
                  });

                  await _notifyAdmin('worker_removed', 'Worker Removed', 'Supervisor removed $name. Reason: $finalReason');
                  
                  // Lookup StaffID
                  String? sId;
                  try {
                    final d = _assignedStaff.firstWhere((e) => e.id == uid);
                    sId = (d.data() as Map<String, dynamic>)['staffId'];
                  } catch (_) {}

                  await _sendSingleWorkerNotification(uid, sId, 'worker_removed', 'Removed from Job', 'You have been removed from this job (${_data?['category'] ?? "Task"}). Reason: $finalReason');
                  
                  // Notify REMAINING Team (Bystanders)
                  for (var doc in _assignedStaff) {
                      if (doc.id == uid) continue; // Don't notify value again
                      final d = doc.data() as Map<String, dynamic>;
                      await _sendSingleWorkerNotification(doc.id, d['staffId'], 'team_update', 'Team Update', '$name was removed from the team.');
                  }
                  
                  setState(() => _actionLoading = false);
                  _fetch(); // Refresh list
                  if(mounted) _showSuccess("Worker Removed", "$name has been removed from the team.");
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
                child: Text("Confirm Removal", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      );
    }));
  }
  
    // ✅ NEW: Show Attendance History for Worker (Robust ID Search)
    void _showWorkerAttendance(String staffId, String docId, String workerName) {
      // Build search keys (Staff ID + Doc ID)
      final searchIds = [staffId, docId].where((s) => s.isNotEmpty).toList();

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.purple[50], shape: BoxShape.circle),
                            child: Icon(Icons.history_edu_rounded, color: Colors.purple[700], size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Attendance Log", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text("For $workerName (Task Specific)", style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                        ],
                      ),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('attendance')
                        .where('workerId', whereIn: searchIds) // ✅ Robust Search (Staff ID or Doc ID)
                        .where('taskId', isEqualTo: _id)       // ✅ STRICT Task Scoping
                        .limit(20)
                        .snapshots(),
                    builder: (context, snapshot) {
                       if (snapshot.hasError) {
                         return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                       }
                       
                       if (snapshot.connectionState == ConnectionState.waiting) {
                         return const Center(child: CircularProgressIndicator(color: Colors.purple));
                       }

                       if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                         return Center(
                           child: Column(
                             mainAxisAlignment: MainAxisAlignment.center,
                             children: [
                               Icon(Icons.history_toggle_off_rounded, size: 50, color: Colors.grey[300]),
                               const SizedBox(height: 10),
                               Text("No Attendance Records", style: GoogleFonts.outfit(color: Colors.grey[500], fontWeight: FontWeight.bold)),
                               const SizedBox(height: 5),
                               Text("Worker has not clocked in for this job yet.", style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 12)),
                             ],
                           ),
                         );
                       }
  
                       final docs = snapshot.data!.docs;
                       
                       // Manual sort (Newest first) - Client side for simpler indexing
                       docs.sort((a, b) {
                         final tA = (a['timestamp'] as Timestamp?)?.toDate() ?? DateTime(2000);
                         final tB = (b['timestamp'] as Timestamp?)?.toDate() ?? DateTime(2000);
                         return tB.compareTo(tA);
                       });
  
                       return ListView.builder(
                         controller: scrollController,
                         padding: const EdgeInsets.symmetric(horizontal: 24),
                         itemCount: docs.length,
                         itemBuilder: (context, index) {
                           final data = docs[index].data() as Map<String, dynamic>;
                           final ts = (data['checkIn'] ?? data['timestamp']) as Timestamp?;
                           final checkOutTs = data['checkOut'] as Timestamp?;
                           
                           if(ts == null) return const SizedBox();
  
                           final date = ts.toDate();
                           final dateStr = DateFormat('MMM dd, yyyy').format(date);
                           final inTimeStr = DateFormat('hh:mm a').format(date);
                           
                           String outTimeStr = "--:--";
                           if (checkOutTs != null) {
                              outTimeStr = DateFormat('hh:mm a').format(checkOutTs.toDate());
                           }
  
                           final status = data['status'] ?? 'Present';
                           final isLate = status == 'Late';
  
                           return Container(
                             margin: const EdgeInsets.only(bottom: 12),
                             padding: const EdgeInsets.all(16),
                             decoration: BoxDecoration(
                               color: Colors.white,
                               borderRadius: BorderRadius.circular(16),
                               border: Border.all(color: Colors.grey[200]!),
                             ),
                             child: Row(
                               children: [
                                 Container(
                                   padding: const EdgeInsets.all(10),
                                   decoration: BoxDecoration(
                                       color: isLate ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1), 
                                       shape: BoxShape.circle
                                   ),
                                   child: Icon(
                                       isLate ? Icons.warning_amber_rounded : Icons.check_circle_rounded, 
                                       color: isLate ? Colors.orange : Colors.green, 
                                       size: 18
                                   ),
                                 ),
                                 const SizedBox(width: 16),
                                 Expanded(
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Text(dateStr, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14)),
                                       const SizedBox(height: 4),
                                       Row(
                                         children: [
                                            Text("IN: ", style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                                            Text(inTimeStr, style: GoogleFonts.outfit(fontSize: 12, color: Colors.black87)),
                                            const SizedBox(width: 12),
                                            Text("OUT: ", style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                                            Text(outTimeStr, style: GoogleFonts.outfit(fontSize: 12, color: Colors.black87)),
                                         ],
                                       )
                                     ],
                                   ),
                                 ),
                               ],
                             ),
                           );
                         },
                       );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

  void _showAddWorker() {
    List<String> selIds = [];
    List<String> selNames = [];
    // Filter _crew to only show those NOT currently assigned
    final currentIds = _assignedStaff.map((d) => d.id).toSet();
    final availableCrew = _crew.where((w) => !currentIds.contains(w['docId'])).toList(); 

    if (availableCrew.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No other available workers found for this category.")));
      return;
    }

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => StatefulBuilder(builder: (c, st) => Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
        const SizedBox(height: 24),
        Text("Add Team Member", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        Expanded(child: ListView.separated(
          itemCount: availableCrew.length,
          separatorBuilder: (_,__) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) {
            final w = availableCrew[i];
            bool isSel = selIds.contains(w['docId']);
            return InkWell(
              onTap: () => st(() { if(isSel) { selIds.remove(w['docId']); selNames.remove(w['fullName']); } else { selIds.add(w['docId']); selNames.add(w['fullName']); } }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: isSel ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isSel ? Colors.black : Colors.grey[200]!)),
                child: Row(children: [
                   CircleAvatar(backgroundColor: isSel ? Colors.white : Colors.grey[100], radius: 14, child: Text(w['fullName'][0], style: GoogleFonts.outfit(color: isSel ? Colors.black : Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 12))),
                   const SizedBox(width: 12),
                   Text(w['fullName'], style: GoogleFonts.outfit(color: isSel ? Colors.white : Colors.black, fontWeight: FontWeight.w600, fontSize: 16)),
                   const Spacer(),
                   if(isSel) const Icon(Icons.check_circle, color: Colors.white, size: 20)
                ]),
              ),
            );
          },
        )),
        
        const SizedBox(height: 20),
        SizedBox(height: 56, width: double.infinity, child: ElevatedButton(
        onPressed: selIds.isEmpty ? null : () async {
          Navigator.pop(context);
          setState(() => _actionLoading = true);
          
          try {
              final batch = FirebaseFirestore.instance.batch();
              
              // 1. Update Report
              final rRef = FirebaseFirestore.instance.collection('all_reports').doc(_id);
              batch.update(rRef, {
                'workers': FieldValue.arrayUnion(selNames),
                'workerIds': FieldValue.arrayUnion(selIds)
              });

              // 2. Update Workers
              for (String uid in selIds) {
                 final wRef = FirebaseFirestore.instance.collection('staff').doc(uid);
                 batch.update(wRef, {
                   'status': 'In-Work',
                   'currentReportId': _id,
                 });
              }
              
              await batch.commit(); // ✅ Single Commit
              
              await _notifyAdmin('worker_added', 'Worker Added', 'Supervisor added ${selNames.length} new member(s) to the team.');

              // Notify NEW Workers
              for (String uid in selIds) {
                  // Lookup StaffID
                  String? sId;
                  try {
                    final wData = _crew.firstWhere((element) => element['docId'] == uid, orElse: () => {});
                    sId = wData['staffId'];
                  } catch (_) {}
                  await _sendSingleWorkerNotification(uid, sId, 'assignment', 'New Job Assignment', 'You have been added to the team for: ${_data?['category'] ?? "Task"}');
              }

              // Notify EXISTING Team (Bystanders)
              for (var doc in _assignedStaff) {
                 final d = doc.data() as Map<String, dynamic>;
                 await _sendSingleWorkerNotification(doc.id, d['staffId'], 'team_update', 'Team Update', 'New member(s) added: ${selNames.join(", ")}');
              }

              setState(() => _actionLoading = false);
              _fetch();
              if(mounted) _showSuccess("Members Added", "Successfully added ${selNames.length} new member(s).");

          } catch (e) {
              setState(() => _actionLoading = false);
              if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
          }
        },
        style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: Text("Add Selected", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
      ))
    ]),
  )));
}


void _complete() {
  showModalBottomSheet(
    context: context, 
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(builder: (c, st) => _CompleteJobSheet(
      onConfirm: (File image) async {
        // 1. Validate Location
        try {
           LocationPermission permission = await Geolocator.checkPermission();
           if (permission == LocationPermission.denied) {
              permission = await Geolocator.requestPermission();
              if (permission == LocationPermission.denied) throw "Location permission is required.";
           }

           // ✅ Added Timeout to prevent infinite loading if GPS is stuck
           final position = await Geolocator.getCurrentPosition(
             desiredAccuracy: LocationAccuracy.high, 
             timeLimit: const Duration(seconds: 10)
           );
           
           double? rLat = _data?['lat'];
           double? rLng = _data?['lng'];
             
             // GeoPoint fallback
             if(rLat == null) {
                final loc = _data?['location'];
                if(loc != null) { rLat = loc.latitude; rLng = loc.longitude; }
             }

             if (rLat != null && rLng != null) {
                double dist = Geolocator.distanceBetween(position.latitude, position.longitude, rLat, rLng);
                // 200m Threshold
                if (dist > 200) { 
                   if(mounted) showDialog(context: context, builder: (c) => CustomDialog(
                      icon: Icons.location_off_rounded,
                      title: "Location Mismatch",
                      subtitle: "You are ${dist.toInt()}m away from the site. Completion requires being on-site.",
                      primaryActionText: "OK",
                      onPrimaryAction: () => Navigator.pop(c)
                   ));
                   return; // Stop loading, keep sheet open
                }
             }
          } catch(e) {
             print("Loc Error: $e");
             if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Location check failed: $e")));
             return; 
          }

          // 2. Proceed to Upload
          Navigator.pop(ctx);
          setState(() => _actionLoading = true);
          try {
            final ref = FirebaseStorage.instance.ref().child('completion_evidence').child('${_id}_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await ref.putFile(image);
            final url = await ref.getDownloadURL();

            // ✅ Release Workers (Robust Method)
            final associatedWorkers = await FirebaseFirestore.instance
                .collection('staff')
                .where('currentReportId', isEqualTo: _id)
                .get();

            if (associatedWorkers.docs.isNotEmpty) {
               final batch = FirebaseFirestore.instance.batch();
               for (var doc in associatedWorkers.docs) {
                  batch.update(doc.reference, {
                     'status': 'Available',
                     'currentTeamId': FieldValue.delete(),
                     'currentReportId': FieldValue.delete()
                  });
               }
               await batch.commit();
            }

            await FirebaseFirestore.instance.collection('all_reports').doc(_id).update({
              'status': 'Resolved', 
              'completedAt': DateTime.now().millisecondsSinceEpoch,
              'completionPhoto': url
            });
            await _notifyAdmin('complete', 'Job Completed', 'Supervisor has verified and completed the job.');
            await _notifyUser('Report Resolved', 'Work on your report has been completed.');
            await _notifyWorkers('Job Completed', 'The job has been marked as completed. Great work!', type: 'success'); // ✅ Notify Workers
            setState(() => _actionLoading = false);
            _fetch();
            if(mounted) _showSuccess("Job Completed", "Report resolved & evidence submitted.");
          } catch (e) {
            print(e);
            if(mounted) {
              setState(() => _actionLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
            }
          }
        }
      ))
    );
  }
  Widget _buildWorkerCard(QueryDocumentSnapshot doc, String s, bool started) {
    final data = doc.data() as Map<String, dynamic>;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white, 
        border: Border.all(color: Colors.grey[200]!), 
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(data['fullName'][0], style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['fullName'] ?? "Unknown", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
                Text(data['specialization'] ?? "Worker", style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
          if (s != 'Resolved' && started) ...[
            // Check Attendance Button
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: Colors.deepPurple[50], borderRadius: BorderRadius.circular(10)),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showWorkerAttendance(data['staffId'] ?? "", doc.id, data['fullName']),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.history_edu_rounded, size: 20, color: Colors.deepPurple[700]),
                ),
              ),
            ),
            // Replace Button
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showReplaceWorker(doc.id, data['fullName']),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.swap_horiz_rounded, size: 20, color: Colors.blue[700]),
                ),
              ),
            ),
            // Remove Button
            Container(
              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10)),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showRemoveWorker(doc.id, data['fullName']),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red[700]),
                ),
              ),
            )
          ]
        ],
      ),
    );
  }

  void _showAllWorkers() {
    String s = _data?['status'] ?? "";
    bool started = _data?.containsKey('startedAt') ?? false;

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true,
      backgroundColor: Colors.transparent, 
      builder: (ctx) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Assigned Team (${_assignedStaff.length})", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: _assignedStaff.map((doc) => _buildWorkerCard(doc, s, started)).toList(),
              ),
            )
          ],
        ),
      )
    );
  }

}

class _CompleteJobSheet extends StatefulWidget {
  final Function(File) onConfirm;
  const _CompleteJobSheet({required this.onConfirm});

  @override
  State<_CompleteJobSheet> createState() => _CompleteJobSheetState();
}

class _CompleteJobSheetState extends State<_CompleteJobSheet> {
  File? _image;
  bool _isLoading = false; // Internal loading state
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
    if(img != null) setState(() => _image = File(img.path));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Complete Job", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Text("Capture a clear photo of the completed work.", style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 14)),
          const SizedBox(height: 30),
          
          if (_image == null)
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200, width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[50], 
                  borderRadius: BorderRadius.circular(20), 
                  border: Border.all(color: Colors.grey.shade300, width: 2, style: BorderStyle.solid), 
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 24)),
                    const SizedBox(height: 16),
                    Text("Tap to capture", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14))
                  ],
                ),
              ),
            )
          else
            Column(children: [
              ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(_image!, height: 250, width: double.infinity, fit: BoxFit.cover)),
              const SizedBox(height: 15),
              TextButton.icon(
                onPressed: _pickImage, 
                style: TextButton.styleFrom(foregroundColor: Colors.black),
                icon: const Icon(Icons.refresh, size: 18), 
                label: Text("Retake Photo", style: GoogleFonts.outfit(fontWeight: FontWeight.w600))
              )
            ]),

          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              onPressed: (_image == null || _isLoading) ? null : () async {
                 setState(() => _isLoading = true);
                 await widget.onConfirm(_image!);
                 if(mounted) setState(() => _isLoading = false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black, 
                disabledBackgroundColor: Colors.grey[200],
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
              ),
              child: _isLoading 
                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : Text("Verify & Complete", style: GoogleFonts.poppins(color: _image == null ? Colors.grey[400] : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }


}