import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supervisor_notifications_screen.dart';
import '../widgets/custom_dialog.dart';
import 'supervisor_login_screen.dart';
import 'package:intl/intl.dart';

class SupervisorHomeScreen extends StatefulWidget {
  const SupervisorHomeScreen({super.key});
  @override
  State<SupervisorHomeScreen> createState() => _SupervisorHomeScreenState();
}

class _SupervisorHomeScreenState extends State<SupervisorHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _teamId = ""; 
  String _category = "Loading...";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = prefs.getString('team_id') ?? "";
    final snap = await FirebaseFirestore.instance.collection('teams').where('teamId', isEqualTo: tid).limit(1).get();
    if (snap.docs.isNotEmpty && mounted) {
      setState(() {
        _teamId = tid;
        _category = snap.docs.first.data()['category'] ?? "Unit";
      });
      _checkDeadlines(tid);
    }
  }

  Future<void> _checkDeadlines(String tid) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();

      final snap = await FirebaseFirestore.instance.collection('all_reports')
          .where('assignedTeamId', isEqualTo: tid)
          .where('status', isEqualTo: 'In-progress')
          .get();

      for (var doc in snap.docs) {
        final data = doc.data();
        if (data.containsKey('estimatedDate')) {
          final due = (data['estimatedDate'] as Timestamp).toDate();
          final diff = due.difference(now).inHours;
          
          if (diff < 48) { // Alert if less than 48 hours
             final key = 'last_alert_${doc.id}';
             final lastSent = prefs.getInt(key) ?? 0;
             
             if (lastSent < today) {
               await FirebaseFirestore.instance.collection('notifications').add({
                 'targetTeamId': tid,
                 'title': diff < 0 ? 'Deadline Missed' : 'Deadline Approaching',
                 'message': 'Task ${data['adminReportId']} is ${diff < 0 ? "overdue" : "due soon"}. Please review.',
                 'timestamp': FieldValue.serverTimestamp(),
                 'isRead': false,
                 'type': 'system_alert',
                 'reportId': doc.id
               });
               await prefs.setInt(key, today);
             }
          }
        }
      }
    } catch (e) {
      print("Error checking deadlines: $e");
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SupervisorLoginScreen()), (route) => false);
  }

  void _showLogout() {
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (context) => CustomDialog(
        icon: Icons.logout_rounded, 
        title: "Log out from Fixit Lanka?", 
        subtitle: "You will be taken back to the login screen.", 
        primaryActionText: "Logout", 
        onPrimaryAction: _handleLogout,
        secondaryActionText: "Stay",
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _showLogout();
      },
      child: Scaffold(
        backgroundColor: Colors.white, // Pure White Background
        appBar: AppBar(
          backgroundColor: Colors.white, 
          elevation: 0, 
          toolbarHeight: 90, 
          automaticallyImplyLeading: false,
          flexibleSpace: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('SUPERVISOR PORTAL', style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
                    Text(_teamId, style: GoogleFonts.outfit(color: Colors.black, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
                  ]),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SupervisorNotificationsScreen(teamId: _teamId))),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('notifications')
                          .where('targetTeamId', isEqualTo: _teamId)
                          .where('isRead', isEqualTo: false)
                          .snapshots(),
                      builder: (context, notifSnap) {
                        bool showDot = notifSnap.hasData && notifSnap.data!.docs.isNotEmpty;
                        
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
                            ),
                            if (showDot)
                              Positioned(
                                top: -2, right: -2,
                                child: Container(
                                  width: 12, height: 12,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF3D00), 
                                    shape: BoxShape.circle, 
                                    border: Border.all(color: Colors.white, width: 2)
                                  ),
                                ),
                              )
                          ],
                        );
                      }
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
        body: Column(children: [
        _buildHero(),
        Container(
          height: 60,
          decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
          child: TabBar(
            controller: _tabController, 
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey[400],
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
            indicatorColor: Colors.black,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label, // Apple style: Indicator matches text width
            splashFactory: NoSplash.splashFactory, // No Ripple
            overlayColor: MaterialStateProperty.all(Colors.transparent), // No Hover
            dividerColor: Colors.transparent, // Remove Material divider
            padding: const EdgeInsets.symmetric(horizontal: 16),
            tabs: const [Tab(text: "Assigned"), Tab(text: "Active"), Tab(text: "On Hold"), Tab(text: "History")],
          ),
        ),
        Expanded(child: TabBarView(controller: _tabController, children: [
          _ReportStream(teamId: _teamId, status: 'In-progress', isStarted: false),
          _ReportStream(teamId: _teamId, status: 'In-progress', isStarted: true),
          _ReportStream(teamId: _teamId, status: 'On-Hold', isStarted: null),
          _ReportStream(teamId: _teamId, status: 'Resolved', isStarted: null),
        ])),
      ]),
      ),
    );
  }

  Widget _buildHero() => Container(
    margin: const EdgeInsets.fromLTRB(20, 20, 20, 10), 
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF111111), Color(0xFF2d2d2d)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center, // Align center vertically
      children: [
        Expanded( // Fix overflow by taking available space
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              Text(
                _category.toUpperCase(), 
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                maxLines: 2, // Allow breaking into 2 lines
                overflow: TextOverflow.ellipsis, // Handle overflow
              ),
              const SizedBox(height: 8), // Better spacing
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min, // Wrap content
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF00FF94), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Flexible( // Prevent overflow in badge too
                      child: Text("Oversight Active", style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ]
          ),
        ),
        const SizedBox(width: 16), // Spacing between text and icon
        const Icon(Icons.admin_panel_settings_outlined, color: Colors.white24, size: 50),
      ]
    ),
  );
}

class _ReportStream extends StatelessWidget {
  final String teamId, status; final bool? isStarted;
  const _ReportStream({required this.teamId, required this.status, required this.isStarted});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('all_reports').where('assignedTeamId', isEqualTo: teamId).where('status', isEqualTo: status).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.black));
        final docs = snap.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          if (status == 'In-progress' && isStarted != null) return isStarted! ? data.containsKey('startedAt') : !data.containsKey('startedAt');
          return true;
        }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))]),
                  child: Icon(Icons.assignment_turned_in_outlined, size: 48, color: Colors.grey[300]),
                ),
                const SizedBox(height: 24),
                Text("No Tasks Found", style: GoogleFonts.outfit(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text("There are no tasks in this category yet.", style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey[500], fontWeight: FontWeight.w500)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40), itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _JobCard(
              id: data['adminReportId'] ?? 'ID', 
              category: data['category'] ?? 'Task', 
              location: data['locationName'] ?? 'Site',
              img: (data['photos'] != null && (data['photos'] as List).isNotEmpty) ? data['photos'][0] : null,
              statusLabel: status == 'Resolved' ? 'COMPLETED' : (status == 'On-Hold' ? 'ON HOLD' : (data.containsKey('startedAt') ? 'ACTIVE' : 'ASSIGNED')),
              onTap: () => Navigator.pushNamed(context, '/supervisor-job-details', arguments: docs[index].id),
              date: data.containsKey('assignedAt') 
                  ? (data['assignedAt'] is int 
                      ? DateTime.fromMillisecondsSinceEpoch(data['assignedAt']) 
                      : (data['assignedAt'] as Timestamp).toDate()) 
                  : (data.containsKey('timestamp') ? (data['timestamp'] as Timestamp).toDate() : DateTime.now()),
              estimatedDate: data.containsKey('estimatedDate') ? (data['estimatedDate'] as Timestamp).toDate() : null,
            );
          },
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  final String id, category, location, statusLabel; final String? img; final VoidCallback onTap; final DateTime date; final DateTime? estimatedDate;
  const _JobCard({required this.id, required this.category, required this.location, required this.statusLabel, this.img, required this.onTap, required this.date, this.estimatedDate});

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 1) return "${diff.inDays}d ago";
    if (diff.inHours > 0) return "${diff.inHours}h ago";
    if (diff.inMinutes > 0) return "${diff.inMinutes}m ago";
    return "Just now";
  }

  String _formatDue(DateTime? d) {
    if (d == null) return "No Deadline";
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return "Due: ${months[d.month - 1]} ${d.day}";
  }

  @override
  Widget build(BuildContext context) {
    Color sColor;
    if (statusLabel == 'COMPLETED') sColor = const Color(0xFF00C853);
    else if (statusLabel == 'ACTIVE') sColor = const Color(0xFF2962FF);
    else if (statusLabel == 'ON HOLD') sColor = const Color(0xFFFFAB00);
    else sColor = Colors.black; // ASSIGNED

    Color bgBadge = sColor.withOpacity(0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(24), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))]
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24), onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16), 
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 90, height: 90, 
                      decoration: BoxDecoration(
                        color: Colors.grey[100], 
                        borderRadius: BorderRadius.circular(18), 
                        image: img != null ? DecorationImage(image: NetworkImage(img!), fit: BoxFit.cover) : null
                      ), 
                      child: img == null ? Icon(Icons.image_outlined, color: Colors.grey[400]) : null
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, 
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), 
                                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)), 
                                child: Text(id, style: GoogleFonts.robotoMono(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
                              ),
                              // Removed "Just now"
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(category, style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[400]),
                            const SizedBox(width: 4),
                            Expanded(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500))),
                          ]),
                        ],
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(width: double.infinity, height: 1, color: Colors.grey[50]),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // New "Assigned Date" details
                    Row(children: [
                      Icon(Icons.access_time_rounded, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 6),
                      Text(
                        "Assigned: ${DateFormat('dd MMM, hh:mm a').format(date)}", 
                        style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w600)
                      ), 
                    ]),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                      decoration: BoxDecoration(color: bgBadge, borderRadius: BorderRadius.circular(10)), 
                      child: Text(statusLabel, style: GoogleFonts.outfit(color: sColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5))
                    ),
                  ],
                )
              ],
            )
          ),
        ),
      ),
    );
  }
}