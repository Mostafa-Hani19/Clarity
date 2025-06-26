import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../routes/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';

class HelperConnectionStatus extends StatelessWidget {
  final bool showConnectAction;
  
  const HelperConnectionStatus({
    super.key,
    this.showConnectAction = true,
  });

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive sizing
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    // ignore: unused_local_variable
    final isLandscape = screenSize.width > screenSize.height;
    
    // Responsive sizing values
    final iconSize = isSmallScreen ? 20.0 : 24.0;
    final containerPadding = isSmallScreen ? 6.0 : 8.0;
    final horizontalPadding = isSmallScreen ? 12.0 : 16.0;
    final verticalPadding = isSmallScreen ? 8.0 : 12.0;
    final spacingWidth = isSmallScreen ? 8.0 : 12.0;
    final buttonHorizontalPadding = isSmallScreen ? 8.0 : 12.0;
    final buttonVerticalPadding = isSmallScreen ? 4.0 : 6.0;
    final statusFontSize = isSmallScreen ? 11.0 : 13.0;
    final detailsFontSize = isSmallScreen ? 12.0 : 14.0;
    final buttonFontSize = isSmallScreen ? 11.0 : 13.0;
    final buttonCornerRadius = isSmallScreen ? 8.0 : 12.0;
    
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final isLinked = authProvider.isLinkedWithUser;
        // ignore: unused_local_variable
        final linkedUserId = authProvider.linkedUserId;
        
        return Card(
          elevation: 2,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: horizontalPadding,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(containerPadding),
                  decoration: BoxDecoration(
                    color: isLinked 
                        ? Colors.green.withOpacity(0.1) 
                        : Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isLinked ? Icons.person : Icons.person_outline,
                    color: isLinked ? Colors.green : Colors.blue,
                    size: iconSize,
                  ),
                ),
                SizedBox(width: spacingWidth),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isLinked ? 'connected'.tr() : 'not_connected'.tr(),
                        style: TextStyle(
                          fontSize: statusFontSize, 
                          color: isLinked ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isLinked ? 'connected_to_helper'.tr() : 'not_connected_to_helper'.tr(),
                        style: TextStyle(
                          fontSize: detailsFontSize,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => context.push(AppRouter.blindUserProfile),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: buttonHorizontalPadding, 
                      vertical: buttonVerticalPadding,
                    ),
                    textStyle: TextStyle(
                      fontSize: buttonFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(buttonCornerRadius),
                    ),
                  ),
                  child: Text(isLinked ? 'view'.tr() : 'connect'.tr()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 