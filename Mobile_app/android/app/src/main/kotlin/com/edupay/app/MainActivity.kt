package com.edupay.app

import io.flutter.embedding.android.FlutterActivity

/**
 * FIX: Changed FlutterFragmentActivity → FlutterActivity
 *
 * FlutterFragmentActivity causes BLASTBufferQueue buffer overflow
 * on Xiaomi MIUI devices with Vulkan/Impeller rendering backend.
 * The SurfaceView created by FlutterFragmentActivity acquires too many
 * buffers (4 > max:2+2), which exhausts the buffer queue and crashes
 * the rendering pipeline — causing "Lost connection to device".
 *
 * FlutterActivity uses a different surface attachment strategy that
 * does not overflow the buffer queue on MIUI.
 */
class MainActivity : FlutterActivity()