-- Minimal starter data. Replace names before running in production.
INSERT INTO organizations (id, name, currency, timezone)
VALUES ('00000000-0000-0000-0000-000000000001', 'My Restaurant Group', 'BDT', 'Asia/Dhaka');

INSERT INTO permissions (code, description) VALUES
 ('inventory.view','See stock levels'),
 ('inventory.view_cost','See costs and values'),
 ('po.create','Create purchase orders'),
 ('po.approve','Approve purchase orders'),
 ('receive','Receive vendor deliveries at Central'),
 ('tr.request','Request stock for a branch'),
 ('tr.approve','Approve branch stock requests (Owner)'),
 ('tr.dispatch','Pick and dispatch stock from Central'),
 ('tr.receive','Confirm a delivery at a branch'),
 ('dist.approve','Approve daily distribution plans (Owner)'),
 ('waste.create','Log waste'),
 ('waste.approve','Approve waste above the limit'),
 ('count.perform','Perform stock counts'),
 ('count.approve','Approve counts and post adjustments'),
 ('adj.create','Request stock adjustments'),
 ('adj.approve','Approve stock adjustments'),
 ('consume','Record kitchen usage'),
 ('lot.manage','Quarantine, release and write off batches'),
 ('master','Manage products, suppliers, branches and lists'),
 ('invoice.edit','Edit invoices'),
 ('audit.view','View the audit log'),
 ('user.manage','Invite and manage users (Owner)');

-- Roles (one row per role key; attach permissions per your policy)
INSERT INTO roles (organization_id, key, name) VALUES
 ('00000000-0000-0000-0000-000000000001','owner','Owner (Super Admin)'),
 ('00000000-0000-0000-0000-000000000001','admin','Admin'),
 ('00000000-0000-0000-0000-000000000001','inventory_manager','Inventory Manager'),
 ('00000000-0000-0000-0000-000000000001','branch_manager','Branch Manager'),
 ('00000000-0000-0000-0000-000000000001','storekeeper','Storekeeper'),
 ('00000000-0000-0000-0000-000000000001','kitchen_manager','Kitchen Manager'),
 ('00000000-0000-0000-0000-000000000001','auditor','Auditor'),
 ('00000000-0000-0000-0000-000000000001','viewer','Viewer');

-- Central warehouse (required: branches can only be supplied from here)
INSERT INTO locations (organization_id, type, name)
VALUES ('00000000-0000-0000-0000-000000000001','central','Central Warehouse');

-- Base units
INSERT INTO units (organization_id, code, dimension) VALUES
 ('00000000-0000-0000-0000-000000000001','kg','mass'),
 ('00000000-0000-0000-0000-000000000001','g','mass'),
 ('00000000-0000-0000-0000-000000000001','L','volume'),
 ('00000000-0000-0000-0000-000000000001','ml','volume'),
 ('00000000-0000-0000-0000-000000000001','pc','count'),
 ('00000000-0000-0000-0000-000000000001','pack','count'),
 ('00000000-0000-0000-0000-000000000001','carton','count');

INSERT INTO number_sequences (organization_id, doc_type, prefix) VALUES
 ('00000000-0000-0000-0000-000000000001','PO','PO-'),
 ('00000000-0000-0000-0000-000000000001','GRN','GRN-'),
 ('00000000-0000-0000-0000-000000000001','TR','TR-'),
 ('00000000-0000-0000-0000-000000000001','INV','INV-'),
 ('00000000-0000-0000-0000-000000000001','WS','WS-'),
 ('00000000-0000-0000-0000-000000000001','ADJ','ADJ-'),
 ('00000000-0000-0000-0000-000000000001','CNT','CNT-'),
 ('00000000-0000-0000-0000-000000000001','DP','DP-'),
 ('00000000-0000-0000-0000-000000000001','TXN','TXN-');
