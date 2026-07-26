/**
 * socket_broadcast.js
 *
 * Centralised helper for emitting Socket.IO events.
 *
 * Room strategy:
 *  - Every branch user joins `branch-<branchId>`.
 *  - Superadmin clients join the special `all_rooms` room so they receive
 *    every branch event without being listed in each branch room.
 *
 * Room membership by role:
 *  - karyawan / admin  → joins `branch-<branchId>` only
 *  - superadmin        → joins `all_rooms` only
 *
 * Broadcast targets:
 *  - product / category events → `branch-<branchId>` + `all_rooms`
 *  - transaction events        → `branch-<branchId>` + `all_rooms`
 *  - global events (branchId=0)→ `all_rooms` only
 *
 * Usage:
 *   const { broadcastToRoom } = require('../utils/socket_broadcast');
 *   broadcastToRoom(io, branchId, 'product-updated', productData);
 */

/**
 * Emit `event` + `data` to the branch room AND the superadmin catch-all.
 *
 * @param {import('socket.io').Server} io
 * @param {number|string} branchId - Pass 0 for global / category events
 * @param {string} event
 * @param {*} data
 */
function broadcastToRoom(io, branchId, event, data) {
  if (!io) return;

  if (!branchId || branchId === 0) {
    // Global events (e.g. categories) — only superadmin needs them
    io.to('all_rooms').emit(event, data);
  } else {
    // Branch-scoped events — notify every connected client in that branch
    // AND the superadmin catch-all room
    io.to([`branch-${branchId}`, 'all_rooms']).emit(event, data);
  }
}

module.exports = { broadcastToRoom };
