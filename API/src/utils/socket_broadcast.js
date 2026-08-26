/**
 * socket_broadcast.js
 *
 * Centralised helper for emitting Socket.IO events with granular subscriptions.
 *
 * Room strategy:
 *  - Every branch user joins `branch-<branchId>`.
 *  - Superadmin clients join the special `all_rooms` room so they receive
 *    every branch event without being listed in each branch room.
 *  - Granular subscriptions: clients join `entity-<entityName>` rooms
 *    (e.g., entity-products, entity-vouchers) to receive only subscribed events.
 *
 * Room membership by role:
 *  - karyawan / admin  → joins `branch-<branchId>` only
 *  - superadmin        → joins `all_rooms` only
 *
 * Broadcast targets:
 *  - product / category events → `branch-<branchId>` + `all_rooms` + `entity-products`
 *  - voucher events           → `all_rooms` + `entity-vouchers` (global)
 *  - user events              → `branch-<branchId}` + `all_rooms` + `entity-users`
 *  - transaction events       → `branch-<branchId>` + `all_rooms` + `entity-live_transactions`
 *  - global events (branchId=0)→ `all_rooms` only
 *
 * Usage:
 *   const { broadcastToRoom, broadcastToEntity } = require('../utils/socket_broadcast');
 *   broadcastToRoom(io, branchId, 'product-updated', productData);
 *   broadcastToEntity(io, 'vouchers', 'voucher-created', voucherData);
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

/**
 * Emit `event` + `data` to entity-specific subscribers AND all_rooms.
 * Used for granular subscriptions (products, vouchers, users, live_transactions).
 *
 * @param {import('socket.io').Server} io
 * @param {string} entity - Entity name ('products', 'vouchers', 'users', 'live_transactions')
 * @param {string} event - Event name
 * @param {*} data - Event payload
 * @param {number|null} branchId - Optional branch ID for branch-scoped entities
 */
function broadcastToEntity(io, entity, event, data, branchId = null) {
  if (!io) return;

  const rooms = [`entity-${entity}`, 'all_rooms'];
  
  // For branch-scoped entities, also broadcast to branch room
  if (branchId && branchId !== 0) {
    rooms.push(`branch-${branchId}`);
  }

  io.to(rooms).emit(event, data);
  console.log(`Broadcasted ${event} to entity-${entity} (${rooms.length} rooms)`);
}

module.exports = { broadcastToRoom, broadcastToEntity };
