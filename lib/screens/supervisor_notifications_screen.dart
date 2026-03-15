import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart'; // ✅ Added for Location Validation
import '../widgets/custom_dialog.dart';

class SupervisorNotificationsScreen extends StatefulWidget {
  final String teamId;
  const SupervisorNotificationsScreen({super.key, required this.teamId});

  @override
  State<SupervisorNotificationsScreen> createState() => _SupervisorNotificationsScreenState();
}

class _SupervisorNotificationsScreenState extends State<SupervisorNotificationsScreen> {
  
  @override
  void initState() {
    super.initState();
    _markAllRead();
  }

  Future<void> _markAllRead() async {
    final batch = FirebaseFirestore.instance.batch();
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 24));

    final snap = await FirebaseFirestore.instance.collection('notifications')
        .where('targetTeamId', isEqualTo: widget.teamId)
        .get();

    for(var doc in snap.docs) { 
      final data = doc.data();
      bool isRead = data['isRead'] ?? false;
      Timestamp? ts = data['timestamp'];

      // 1. Mark unread as read
      if (!isRead) {
        batch.update(doc.reference, {'isRead': true});
      }

      // 2. Auto-delete if read AND older than 24h
      if (isRead && ts != null && ts.toDate().isBefore(cutoff)) {
        batch.delete(doc.reference);
      }
    }
    await batch.commit();
  }

  Future<void> _clearAll() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('notifications').where('targetTeamId', isEqualTo: widget.teamId).get();
      
      // ✅ VALIDATION: Check for pending actions
      bool hasPending = snap.docs.any((doc) {
        final data = doc.data();
        final type = data['type'];
        final isReport = type == 'sick_report' || type == 'site_issue';
        // If it's a report and 'verified' is NOT set (null), it's pending.
        return isReport && data['verified'] == null;
      });

      if (hasPending) {
        if(mounted) {
           showDialog(
             context: context,
             builder: (ctx) => CustomDialog(
               icon: Icons.warning_amber_rounded,
               iconColor: Colors.orange,
               iconContainerColor: Colors.orange.withOpacity(0.1),
               title: "Action Required",
               subtitle: "You have pending reports that need verification or decline before clearing.",
               primaryActionText: "OK",
               onPrimaryAction: () => Navigator.pop(ctx),
               secondaryActionText: "", // Hide secondary
             )
           );
        }
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for(var doc in snap.docs) { batch.delete(doc.reference); }
      await batch.commit();
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error clearing: $e")));
    }
  }

  Future<void> _verifyAndReport(String docId, Map<String, dynamic> data) async {
    final reportId = data['reportId'];
    final issueType = data['type'] == 'sick_report' ? 'Sick Report' : 'Site Issue';
    final workerName = data['message']?.split('reported')?.first ?? 'Worker';
    
    // 1. Check Location (Must be on site)
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.black)));
    
    try {
      if (reportId == null) throw "Report ID missing. Cannot verify location.";

      // Get Report Location
      final rDoc = await FirebaseFirestore.instance.collection('all_reports').doc(reportId).get();
      if (!rDoc.exists) throw "Job/Report not found (ID: $reportId)";
      
      final rData = rDoc.data();
      double? rLat = rData?['lat'];
      double? rLng = rData?['lng'];
       
      // Fallback to GeoPoint
      if (rData != null && rData['location'] != null) {
          GeoPoint gp = rData['location'];
          rLat = gp.latitude;
          rLng = gp.longitude;
      }

      if (rLat == null || rLng == null) throw "Job location missing.";

      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, rLat, rLng);

      if (dist > 200) { // 200m Threshold
         Navigator.pop(context); // Close loading
         
         showDialog(
           context: context,
           builder: (ctx) => CustomDialog(
             icon: Icons.location_off_rounded,
             iconColor: Colors.red,
             iconContainerColor: Colors.red.withOpacity(0.1),
             title: "Location Mismatch",
             subtitle: "You must be on-site to verify this issue.\nDistance: ${dist.toInt()}m",
             primaryActionText: "OK",
             onPrimaryAction: () => Navigator.pop(ctx)
           )
         );
         return;
      }
      
      // 2. Verified -> Notify Admin
    await FirebaseFirestore.instance.collection('notifications').add({
      'target': 'admin',
      'type': 'status_update', // Shows in Event Log
      'title': '$issueType Verified',
      'message': 'Supervisor verified $issueType from $workerName.',
      'reportId': reportId,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });
      
      // 3. Verified -> Notify Worker
      // Retrieve Worker ID from the Notification Metadata (Reliable Source)
      final metadata = data['metadata'] as Map<String, dynamic>?;
      final workerTargetId = metadata?['workerId'];
      
      if (workerTargetId != null) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'target': workerTargetId, // Matches worker's _workerDocId or _staffId
          'type': 'status_update',
          'title': 'Report Verified',
          'message': 'Your $issueType has been verified by the supervisor. Admin has been notified.',
          'reportId': reportId,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });
      }

      // Update Local Notification to show clean state (optional, or just delete)
      await FirebaseFirestore.instance.collection('notifications').doc(docId).update({
        'verified': true,
        'isRead': true
      });

      Navigator.pop(context); // Close loading

      showDialog(
         context: context,
         builder: (ctx) => CustomDialog(
           icon: Icons.verified_rounded,
           iconColor: Colors.green,
           iconContainerColor: Colors.green.withOpacity(0.1),
           title: "Verified",
           subtitle: "Issue has been verified and Admin notified.",
           primaryActionText: "OK",
           onPrimaryAction: () => Navigator.pop(ctx),
           secondaryActionText: "" // Remove Cancel button
         )
      );

    } catch (e) {
      if(mounted && Navigator.canPop(context)) Navigator.pop(context);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showDeclineReasonSheet(String docId, Map<String, dynamic> data) {
    String? selectedReason;
    final tc = TextEditingController();
    final reasons = ["Not Checkable", "False Report", "Already Fixed", "Duplicate Report", "Insufficient Evidence"];

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true,
      backgroundColor: Colors.transparent, 
      builder: (ctx) => StatefulBuilder(builder: (c, st) {
         return Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 30),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Auto-height
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
               const SizedBox(height: 24),
               Text("Decline Reason", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
               const SizedBox(height: 16),
               
               // Reason List
               ...reasons.map((r) => RadioListTile<String>(
                  title: Text(r, style: GoogleFonts.outfit(fontWeight: FontWeight.w500)),
                  value: r, groupValue: selectedReason, activeColor: Colors.red, dense: true,
                  onChanged: (v) => st(() => selectedReason = v),
               )),
               RadioListTile<String>(
                  title: Text("Other", style: GoogleFonts.outfit(fontWeight: FontWeight.w500)),
                  value: "Other", groupValue: selectedReason, activeColor: Colors.red, dense: true,
                  onChanged: (v) => st(() => selectedReason = v),
               ),
               if(selectedReason == "Other") 
                 TextField(
                   controller: tc, 
                   decoration: InputDecoration(
                     hintText: "Enter reason...", 
                     isDense: true, 
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                     contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
                   )
                 ),

               const SizedBox(height: 24),
               SizedBox(
                 width: double.infinity, height: 50,
                 child: ElevatedButton(
                   onPressed: (selectedReason == null) ? null : () async {
                      Navigator.pop(ctx);
                      String finalReason = selectedReason == "Other" ? tc.text : selectedReason!;
                      if(finalReason.trim().isEmpty) return;
                      _declineReport(docId, data, finalReason);
                   },
                   style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                   child: Text("Confirm Decline", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                 ),
               )
            ],
          ),
         );
      })
    );
  }

  Future<void> _declineReport(String docId, Map<String, dynamic> data, String reason) async {
    final reportId = data['reportId'];
    final issueType = data['type'] == 'sick_report' ? 'Sick Report' : 'Site Issue';
    final workerName = data['message']?.split('reported')?.first ?? 'Worker';
    
    // Notify Worker Only
    final metadata = data['metadata'] as Map<String, dynamic>?;
    final workerTargetId = metadata?['workerId'];

    if (workerTargetId != null) {
      // Notify Worker
      await FirebaseFirestore.instance.collection('notifications').add({
        'target': workerTargetId,
        'type': 'status_update',
        'title': 'Report Declined',
        'message': 'Your $issueType was declined. Reason: $reason',
        'reportId': reportId,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
    }

    // 2. Decline -> Notify Admin (NEW)
    await FirebaseFirestore.instance.collection('notifications').add({
      'target': 'admin',
      'type': 'status_update',
      'title': '$issueType Declined',
      'message': 'Supervisor declined $issueType from $workerName. Reason: $reason', 
      'reportId': reportId,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });

    // Update Local Doc
    await FirebaseFirestore.instance.collection('notifications').doc(docId).update({
      'verified': false, // or handled
      'isRead': true
    });

    if(mounted) {
      showDialog(
        context: context,
        builder: (ctx) => CustomDialog(
          icon: Icons.cancel_outlined,
          iconColor: Colors.red,
          iconContainerColor: Colors.red.withOpacity(0.1),
          title: "Declined",
          subtitle: "Worker has been notified.",
          primaryActionText: "OK",
          onPrimaryAction: () => Navigator.pop(ctx),
          secondaryActionText: "" // Remove Cancel button
        )
      );
    }
  }



  void _showVerifyDialog(String docId, Map<String, dynamic> data) {
    // Extract Metadata for better context
    final workerName = data['message']?.split(':')?.first ?? 'Worker'; // Simple parse or from metadata
    final rawMsg = data['message']?.split(':')?.last ?? '';
    final details = data['metadata']?['details'] ?? rawMsg.trim();
    final type = data['type'] == 'sick_report' ? 'Sick Report' : 'Site Issue';

    showDialog(
      context: context, 
      builder: (context) => CustomDialog(
        icon: Icons.fact_check_rounded, 
        title: "Verify $type?", 
        subtitle: "Worker: $workerName\nDetails: $details\n\nIs this a valid issue that requires action?", 
        primaryActionText: "Yes, It's Valid", 
        onPrimaryAction: () {
          Navigator.pop(context);
          _verifyAndReport(docId, data);
        },
        secondaryActionText: "Refuse / Decline",
        onSecondaryAction: () {
           Navigator.pop(context);
           _showDeclineReasonSheet(docId, data);
        },
        primaryColor: Colors.black, // Default
        secondaryColor: Colors.red, // Red for Decline
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text("Notifications", style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            onPressed: () {
              showDialog(
                context: context, 
                builder: (context) => CustomDialog(
                  icon: Icons.delete_forever_rounded, 
                  title: "Clear All Notifications?", 
                  subtitle: "This will permanently delete all your updates.", 
                  primaryActionText: "Clear All", 
                  onPrimaryAction: () {
                    _clearAll();
                    Navigator.pop(context);
                  },
                  secondaryActionText: "Cancel",
                  primaryColor: Colors.red,
                )
              );
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 1. ACTION REQUIRED (Deadlines) ---


            // --- 2. NOTIFICATIONS STREAM ---
            Text("UPDATES", style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey[400], letterSpacing: 1.5)),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              // FIXED: Removed orderBy to prevent missing index errors
              stream: FirebaseFirestore.instance.collection('notifications')
                  .where('targetTeamId', isEqualTo: widget.teamId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text("Error loading updates: ${snapshot.error}");
                if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.black)));
                
                final docs = snapshot.data!.docs;
                
                // FIXED: Client-side sorting
                docs.sort((a, b) {
                  Timestamp tA = a['timestamp'] ?? Timestamp.now();
                  Timestamp tB = b['timestamp'] ?? Timestamp.now();
                  return tB.compareTo(tA);
                });

                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Column(
                      children: [
                        Icon(Icons.notifications_off_outlined, size: 40, color: Colors.grey[200]),
                        const SizedBox(height: 10),
                        Text("No updates yet", style: GoogleFonts.outfit(color: Colors.grey[400], fontWeight: FontWeight.bold)),
                      ],
                    )),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (ctx, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final docId = docs[i].id;
                    return _buildNotifCard(data, docId);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(String title, String body, String time, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
              const SizedBox(height: 4),
              Text(body, style: GoogleFonts.outfit(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(time, style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          )
        ],
      ),
    );
  }

  Widget _buildNotifCard(Map<String, dynamic> data, String docId) {
    bool isAssigned = data['type'] == 'assignment'; 
    String title = data['title'] ?? 'Update';
    
    IconData icon = isAssigned ? Icons.assignment_ind : Icons.info_outline;
    Color iconColor = Colors.black;
    Color containerColor = Colors.grey[50]!;

    // Custom Icons for Worker Actions
    if (title.contains("Attendance: Check-In")) { 
      icon = Icons.login_rounded; 
      iconColor = Colors.green; 
      containerColor = Colors.green.withOpacity(0.1);
    }
    else if (title.contains("Attendance: Check-Out")) { 
      icon = Icons.logout_rounded; 
      iconColor = Colors.grey; 
      containerColor = Colors.grey.withOpacity(0.1);
    }
    else if (title.contains("Sick")) { 
      icon = Icons.sick_outlined; 
      iconColor = Colors.red; 
      containerColor = Colors.red.withOpacity(0.1);
    }
    else if (title.contains("Site Issue")) { 
      icon = Icons.report_problem_rounded; 
      iconColor = Colors.orange; 
      containerColor = Colors.orange.withOpacity(0.1);
    }



    // ✅ CLICKABLE FOR VERIFICATION
    if (data['type'] == 'sick_report' || data['type'] == 'site_issue' || title.contains("Site Issue") || title.contains("Report: Sick")) {
       return Padding(
         padding: const EdgeInsets.only(bottom: 12),
         child: InkWell(
           onTap: (data['verified'] != null) ? null : () => _showVerifyDialog(docId, data), // ✅ Disable if Handled
           borderRadius: BorderRadius.circular(20),
           child: Opacity( // Visually dim handled items
             opacity: (data['verified'] != null) ? 0.7 : 1.0, 
             child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[100]!),
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: containerColor, shape: BoxShape.circle),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(data['title'] ?? "Update", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15))),
                          if(data['timestamp'] != null)
                            Text(_formatTime((data['timestamp'] as Timestamp).toDate()), style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 11))
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(data['message'] ?? (data['body'] ?? "No details available"), style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 13, height: 1.4)),
                      if (data['verified'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [Icon(Icons.check_circle, size: 14, color: Colors.green), SizedBox(width: 4), Text("Verified", style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))]),
                        )
                      else if (data['verified'] == false)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [Icon(Icons.cancel, size: 14, color: Colors.red), SizedBox(width: 4), Text("Declined", style: GoogleFonts.outfit(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12))]),
                        )
                    ],
                  ),
                )
              ],
            ),
          ),
         ),
       ),
     );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: containerColor, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(data['title'] ?? "Update", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15))),
                    if(data['timestamp'] != null)
                      Text(_formatTime((data['timestamp'] as Timestamp).toDate()), style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 11))
                  ],
                ),
                const SizedBox(height: 6),
                Text(data['message'] ?? (data['body'] ?? "No details available"), style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 13, height: 1.4)),
              ],
            ),
          )
        ],
      ),
    );
  }

  String _formatTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return DateFormat('MMM d').format(d);
  }
}

