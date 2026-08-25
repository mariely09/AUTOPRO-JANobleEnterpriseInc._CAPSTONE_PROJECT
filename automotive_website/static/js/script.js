 // Demo accounts
        const accounts = {
            customer: {
                username: 'customer',
                password: 'customer123',
                name: 'John Doe',
                role: 'customer',
                avatar: 'JD'
            },
            staff: {
                username: 'staff',
                password: 'staff123',
                name: 'Staff Member',
                role: 'staff',
                avatar: 'ST'
            },
            admin: {
                username: 'admin',
                password: 'admin123',
                name: 'Administrator',
                role: 'admin',
                avatar: 'AD'
            }
        };

        let currentUser = null;
        // Sync with window.currentUser set by staff.js or admin login
        Object.defineProperty(window, 'currentUser', {
            get: function () { return currentUser; },
            set: function (v) { currentUser = v; },
            configurable: true
        });
        let currentEditingAsset = null;

        // Asset database
        let assets = [
            {
                id: 1,
                assetNum: 'ASSET-001',
                plateNumber: 'ABC-1234',
                assetDescription: 'Isuzu Truck NQR 2021',
                type: 'truck',
                icon: '🚛',
                brand: 'Isuzu',
                model: 'NQR',
                yearModel: 2021,
                engineNo: 'ENG-ABC-001',
                chassisNo: 'CHS-ABC-001',
                dateAcquired: '2021-03-15',
                owner: 'John Doe',
                odometer: 45230,
                status: 'active',
                lastServiceDate: '2026-01-15',
                nextPMSDue: '2026-03-15',
                serviceFrequency: 2,
                assignedMechanic: null,
                image: null,
                meters: [
                    { name: 'Odometer', type: 'continuous', value: '45230', unit: 'km' },
                    { name: 'Engine Hours', type: 'continuous', value: '1250', unit: 'hours' }
                ],
                maintenanceHistory: [
                    { date: '2026-01-15', service: 'Change Oil', parts: 'Engine Oil', km: 45230, cost: 450 },
                    { date: '2025-12-10', service: 'Brake Inspection', parts: 'None', km: 43100, cost: 0 },
                    { date: '2025-11-05', service: 'Full PMS', parts: 'Oil, Filters', km: 40000, cost: 2350 }
                ]
            },
            {
                id: 2,
                assetNum: 'ASSET-002',
                plateNumber: 'DEF-2345',
                assetDescription: 'Isuzu Truck ELF 2020',
                type: 'truck',
                icon: '🚛',
                brand: 'Isuzu',
                model: 'ELF',
                yearModel: 2020,
                engineNo: 'ENG-DEF-002',
                chassisNo: 'CHS-DEF-002',
                dateAcquired: '2020-06-10',
                owner: 'John Doe',
                odometer: 78450,
                status: 'active',
                lastServiceDate: '2025-12-20',
                nextPMSDue: '2026-02-20',
                serviceFrequency: 2,
                assignedMechanic: null,
                image: null,
                meters: [
                    { name: 'Odometer', type: 'continuous', value: '78450', unit: 'km' },
                    { name: 'Engine Hours', type: 'continuous', value: '2100', unit: 'hours' }
                ],
                maintenanceHistory: [
                    { date: '2025-12-20', service: 'Full PMS', parts: 'Oil, Filters, Belts', km: 78450, cost: 3200 },
                    { date: '2025-10-05', service: 'Change Oil', parts: 'Engine Oil', km: 73200, cost: 450 }
                ]
            },
            {
                id: 3,
                assetNum: 'ASSET-003',
                plateNumber: 'GHI-3456',
                assetDescription: 'Isuzu Truck FVR 2022',
                type: 'truck',
                icon: '🚛',
                brand: 'Isuzu',
                model: 'FVR',
                yearModel: 2022,
                engineNo: 'ENG-GHI-003',
                chassisNo: 'CHS-GHI-003',
                dateAcquired: '2022-01-20',
                owner: 'John Doe',
                odometer: 32100,
                status: 'active',
                lastServiceDate: '2026-02-01',
                nextPMSDue: '2026-04-01',
                serviceFrequency: 2,
                assignedMechanic: null,
                image: null,
                meters: [
                    { name: 'Odometer', type: 'continuous', value: '32100', unit: 'km' },
                    { name: 'Engine Hours', type: 'continuous', value: '890', unit: 'hours' }
                ],
                maintenanceHistory: [
                    { date: '2026-02-01', service: 'Change Oil', parts: 'Engine Oil', km: 32100, cost: 450 },
                    { date: '2025-11-15', service: 'Brake Inspection', parts: 'Brake Pads', km: 28500, cost: 1200 }
                ]
            },
            {
                id: 4,
                assetNum: 'ASSET-004',
                plateNumber: 'JKL-4567',
                assetDescription: 'Isuzu Truck NPR 2019',
                type: 'truck',
                icon: '🚛',
                brand: 'Isuzu',
                model: 'NPR',
                yearModel: 2019,
                engineNo: 'ENG-JKL-004',
                chassisNo: 'CHS-JKL-004',
                dateAcquired: '2019-09-05',
                owner: 'John Doe',
                odometer: 112300,
                status: 'maintenance',
                lastServiceDate: '2026-01-10',
                nextPMSDue: '2026-03-10',
                serviceFrequency: 2,
                assignedMechanic: null,
                image: null,
                meters: [
                    { name: 'Odometer', type: 'continuous', value: '112300', unit: 'km' },
                    { name: 'Engine Hours', type: 'continuous', value: '3450', unit: 'hours' }
                ],
                maintenanceHistory: [
                    { date: '2026-01-10', service: 'Full PMS', parts: 'Oil, Filters, Spark Plugs', km: 112300, cost: 4500 },
                    { date: '2025-09-20', service: 'Tire Replacement', parts: 'Radial Tires x4', km: 105000, cost: 34000 }
                ]
            },
            {
                id: 5,
                assetNum: 'ASSET-005',
                plateNumber: 'MNO-5678',
                assetDescription: 'Isuzu Truck CYZ 2023',
                type: 'truck',
                icon: '🚛',
                brand: 'Isuzu',
                model: 'CYZ',
                yearModel: 2023,
                engineNo: 'ENG-MNO-005',
                chassisNo: 'CHS-MNO-005',
                dateAcquired: '2023-05-12',
                owner: 'John Doe',
                odometer: 18750,
                status: 'active',
                lastServiceDate: '2026-02-10',
                nextPMSDue: '2026-04-10',
                serviceFrequency: 2,
                assignedMechanic: null,
                image: null,
                meters: [
                    { name: 'Odometer', type: 'continuous', value: '18750', unit: 'km' },
                    { name: 'Engine Hours', type: 'continuous', value: '520', unit: 'hours' }
                ],
                maintenanceHistory: [
                    { date: '2026-02-10', service: 'Change Oil', parts: 'Engine Oil', km: 18750, cost: 450 },
                    { date: '2025-12-01', service: 'General Inspection', parts: 'None', km: 15200, cost: 0 }
                ]
            }
        ];

        let nextAssetId = 6;
        window.assets = assets;

        // Service Transactions database
        let serviceTransactions = [
            {
                serviceId: 'SVC-001',
                dateServiced: '2026-03-20',
                assetNum: 'ASSET-004',
                assetDescription: 'Isuzu Truck NPR 2019',
                mechanicName: 'Juan Dela Cruz',
                servicesRendered: [
                    { description: 'Full PMS - Engine Overhaul', quantity: 1, uom: 'Service', cost: 3500 },
                    { description: 'Brake System Check', quantity: 1, uom: 'Service', cost: 1000 }
                ],
                spareParts: [
                    { itemNum: 'INV-001', name: 'Engine Oil 5W-30', quantity: 4, uom: 'liters', cost: 1800 },
                    { itemNum: 'INV-002', name: 'Brake Pads Set', quantity: 1, uom: 'sets', cost: 1200 }
                ],
                status: 'ongoing',
                totalCost: 7500,
                createdBy: 'Administrator',
                createdOn: '2026-03-20T08:00:00.000Z'
            }
        ];
        let nextServiceId = 2;
        window.serviceTransactions = serviceTransactions;

        // Issuance database
        let issuances = [];
        window.issuances = issuances;
        let nextIssuanceId = 1;

        // Meter Readings database
        let meterReadings = [];
        let nextMeterReadingId = 1;

        // Inventory database
        let inventory = [
            {
                id: 1,
                itemNum: 'INV-001',
                itemId: 'ENG-OIL-001',
                itemName: 'Engine Oil 5W-30',
                longDescription: 'Premium synthetic engine oil 5W-30 for diesel and gasoline engines. Suitable for trucks and buses.',
                barcode: '1234567890123',
                qrcode: 'QR-ENG-OIL-001',
                commodityGroup: 'Lubricants',
                stock: 5,
                unit: 'liters',
                price: 450.00,
                reorderLevel: 10,
                minLevel: 10,
                maxLevel: 50,
                status: 'low_stock',
                lastPhysicalCount: '2026-02-20'
            },
            {
                id: 2,
                itemNum: 'INV-002',
                itemId: 'BRK-PAD-002',
                itemName: 'Brake Pads Set',
                longDescription: 'Heavy duty brake pads for trucks and buses. High performance ceramic compound.',
                barcode: '2345678901234',
                qrcode: 'QR-BRK-PAD-002',
                commodityGroup: 'Spare Parts',
                stock: 2,
                unit: 'sets',
                price: 1200.00,
                reorderLevel: 5,
                minLevel: 5,
                maxLevel: 20,
                status: 'low_stock',
                lastPhysicalCount: '2026-02-20'
            },
            {
                id: 3,
                itemNum: 'INV-003',
                itemId: 'FLT-AIR-003',
                itemName: 'Air Filter',
                longDescription: 'Standard air filter for diesel engines. Compatible with Isuzu and Hino vehicles.',
                barcode: '3456789012345',
                qrcode: 'QR-FLT-AIR-003',
                commodityGroup: 'Filter',
                stock: 15,
                unit: 'units',
                price: 350.00,
                reorderLevel: 8,
                minLevel: 8,
                maxLevel: 40,
                status: 'in_stock',
                lastPhysicalCount: '2026-02-20'
            },
            {
                id: 4,
                itemNum: 'INV-004',
                itemId: 'TIR-RAD-004',
                itemName: 'Radial Tire 10R22.5',
                longDescription: 'Heavy duty radial tire 10R22.5 for trucks. All-weather tread pattern.',
                barcode: '4567890123456',
                qrcode: 'QR-TIR-RAD-004',
                commodityGroup: 'Spare Parts',
                stock: 8,
                unit: 'units',
                price: 8500.00,
                reorderLevel: 4,
                minLevel: 4,
                maxLevel: 16,
                status: 'in_stock',
                lastPhysicalCount: '2026-02-20'
            }
        ];

        let nextInventoryId = 5;
        window.inventory = inventory;
        let physicalCountRecords = [];

        // Login tab switching
        document.getElementById('customerTab')?.addEventListener('click', () => switchLoginTab('customer'));
        document.getElementById('staffTab')?.addEventListener('click', () => switchLoginTab('staff'));
        document.getElementById('adminTab')?.addEventListener('click', () => switchLoginTab('admin'));

        function switchLoginTab(type) {
            document.querySelectorAll('.login-tab').forEach(tab => tab.classList.remove('active'));
            document.querySelectorAll('.login-form-container').forEach(container => container.classList.remove('active'));
            
            document.getElementById(`${type}Tab`).classList.add('active');
            document.getElementById(`${type}Login`).classList.add('active');
        }

        // Customer login
        document.getElementById('customerLoginForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            const username = document.getElementById('customerUsername').value;
            const password = document.getElementById('customerPassword').value;
            
            if (accounts.customer.username === username && accounts.customer.password === password) {
                sessionStorage.setItem('cpUser', JSON.stringify(accounts.customer));
                window.location.href = 'customer_mobileview.html';
            } else {
                alert('Invalid credentials. Please try again.');
            }
        });

        // Staff login
        document.getElementById('staffLoginForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            const username = document.getElementById('staffUsername').value;
            const password = document.getElementById('staffPassword').value;
            
            if (accounts.staff.username === username && accounts.staff.password === password) {
                sessionStorage.setItem('spUser', JSON.stringify(accounts.staff));
                window.location.href = 'staff_mobileview.html';
            } else {
                alert('Invalid credentials. Please try again.');
            }
        });

        // Admin login
        document.getElementById('adminLoginForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            const username = document.getElementById('adminUsername').value;
            const password = document.getElementById('adminPassword').value;
            
            if (accounts.admin.username === username && accounts.admin.password === password) {
                sessionStorage.setItem('apUser', JSON.stringify(accounts.admin));
                window.location.href = 'admin.html';
            } else {
                alert('Invalid credentials. Please try again.');
            }
        });

        function showDashboard(role) {
            // Redirects are handled by login forms — this function is kept for compatibility
        }

        // Logout functions (handled per-portal, kept here for index.html fallback)
        document.getElementById('customerLogoutBtn')?.addEventListener('click', () => logout());
        document.getElementById('staffLogoutBtn')?.addEventListener('click', () => logout());
        document.getElementById('adminLogoutBtn')?.addEventListener('click', () => logout());

        function logout() {
            if (confirm('Are you sure you want to logout?')) {
                window.location.href = 'index.html';
            }
        }

        function switchAdminSection(sectionName) {
            const dashboard = document.getElementById('adminDashboard');
            if (!dashboard) return;

            // Remove active from all nav buttons
            dashboard.querySelectorAll('.admin-nav-btn').forEach(btn => btn.classList.remove('active'));

            // Mark the matching nav button active (null-safe)
            const activeBtn = dashboard.querySelector(`[data-section="${sectionName}"]`);
            if (activeBtn) activeBtn.classList.add('active');

            // Switch content sections
            dashboard.querySelectorAll('.admin-section').forEach(section => section.classList.remove('active'));
            const activeSection = dashboard.querySelector(`#${sectionName}`);
            if (activeSection) activeSection.classList.add('active');

            // Update header title
            const titles = {
                'overview': 'Dashboard Overview',
                'assets': 'Asset Management',
                'asset-servicing': 'Asset Maintenance',
                'issuance': 'Asset Issuance',
                'inventory': 'Stock Inventory',
                'item-master': 'Item Master',
                'inventory-transactions': 'Inventory Transactions',
                'users': 'User Management',
                'reports': 'Reports & Analytics',
                'smart-reports': 'Smart Reports',
                'domains': 'Domain Management',
                'dss': 'Stock Replenishment DSS',
                'dss-pms': 'Preventive Maintenance Scheduling DSS'
            };
            const titleEl = dashboard.querySelector('#currentSectionTitle');
            if (titleEl) titleEl.textContent = titles[sectionName] || 'Admin Panel';

            // Section-specific loaders
            if (sectionName === 'asset-servicing') renderServicesList();
            if (sectionName === 'issuance') renderIssuancesList();
            if (sectionName === 'item-master') { populateItemMasterDropdowns(); renderItemMasterList(); }
            if (sectionName === 'inventory-transactions') renderInventoryTransactions();
            if (sectionName === 'domains') renderDomainsList();
            if (sectionName === 'dss' && typeof renderDSS === 'function') renderDSS();
            if (sectionName === 'dss-pms' && typeof renderDSSPMS === 'function') renderDSSPMS();
            if (sectionName === 'users') renderUsersList();
        }
        // Toggle Asset Management submenu
        function toggleAssetSubmenu(event) {
            event.stopPropagation();
            const submenu = document.getElementById('assetSubmenu');
            const isHidden = submenu.style.display === 'none';
            submenu.style.display = isHidden ? 'block' : 'none';

            // Update arrow icon
            const arrow = event.currentTarget.querySelector('span:last-child');
            if (arrow) {
                arrow.textContent = isHidden ? '▲' : '▼';
            }
        }

        // Toggle Inventory Management submenu
        function toggleInventorySubmenu(event) {
            event.stopPropagation();
            const submenu = document.getElementById('inventorySubmenu');
            const isHidden = submenu.style.display === 'none';
            submenu.style.display = isHidden ? 'block' : 'none';
            const arrow = event.currentTarget.querySelector('span:last-child');
            if (arrow) arrow.textContent = isHidden ? '▲' : '▼';
        }

        // Toggle Reports submenu
        function toggleReportsSubmenu(event) {
            event.stopPropagation();
            const submenu = document.getElementById('reportsSubmenu');
            const isHidden = submenu.style.display === 'none';
            submenu.style.display = isHidden ? 'block' : 'none';
            const arrow = event.currentTarget.querySelector('span:last-child');
            if (arrow) arrow.textContent = isHidden ? '▲' : '▼';
        }

        function toggleDSSSubmenu(event) {
            event.stopPropagation();
            const submenu = document.getElementById('dssSubmenu');
            const isHidden = submenu.style.display === 'none';
            submenu.style.display = isHidden ? 'block' : 'none';
            const arrow = event.currentTarget.querySelector('span:last-child');
            if (arrow) arrow.textContent = isHidden ? '▲' : '▼';
        }

        // Populate Item Master dropdowns from domains
        function populateItemMasterDropdowns() {
            const uomDomain = domains.find(d => d.id === 'UOM');
            const uomList = uomDomain ? uomDomain.list : ['Each', 'Set', 'Hour', 'Piece', 'Litres', 'Gallon'];
            const uomSel = document.getElementById('itemMasterUOM');
            if (uomSel) uomSel.innerHTML = '<option value="">Select UOM</option>' + uomList.map(v => `<option value="${v}">${v}</option>`).join('');

            const cgDomain = domains.find(d => d.id === 'CommodityGroup');
            const cgList = cgDomain ? cgDomain.list : ['Lubricants', 'Spare Parts', 'Filter', 'AutoService'];
            const cgSel = document.getElementById('itemMasterCommodityGroup');
            if (cgSel) cgSel.innerHTML = '<option value="">Select Commodity Group</option>' + cgList.map(v => `<option value="${v}">${v}</option>`).join('');
        }

        function renderCustomerVehicles() {
            const ownerName = currentUser ? currentUser.name : 'John Doe';
            const myAssets = assets.filter(a => a.owner === ownerName);

            const today = new Date();
            today.setHours(0, 0, 0, 0);

            // Compute stats
            const total = myAssets.length;
            const underMaint = myAssets.filter(a => a.status === 'maintenance').length;
            const pmsDueSoon = myAssets.filter(a => {
                if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                const due = new Date(a.nextPMSDue);
                due.setHours(0,0,0,0);
                const diff = Math.ceil((due - today) / (1000*60*60*24));
                return diff >= 0 && diff <= 14;
            }).length;
            const pmsOverdue = myAssets.filter(a => {
                if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                const due = new Date(a.nextPMSDue);
                due.setHours(0,0,0,0);
                return due < today;
            }).length;

            // Render stats
            const statsEl = document.getElementById('customerVehicleStats');
            if (statsEl) {
                statsEl.innerHTML = `
                    <div style="background:#fff;padding:1.75rem;border-radius:16px;color:#1a202c;box-shadow:0 2px 12px rgba(0,0,0,0.08);border:1px solid #e2e8f0;position:relative;overflow:hidden;">
                        <div style="position:absolute;top:-15px;right:-15px;font-size:5rem;opacity:0.05;">🚛</div>
                        <div style="font-size:0.85rem;color:#718096;margin-bottom:0.5rem;font-weight:500;">Total Vehicles</div>
                        <div style="font-size:2.5rem;font-weight:800;color:#1a202c;">${total}</div>
                        <div style="font-size:0.8rem;color:#a0aec0;margin-top:0.3rem;">${ownerName}'s fleet</div>
                    </div>
                    <div style="background:#fff;padding:1.75rem;border-radius:16px;color:#1a202c;box-shadow:0 2px 12px rgba(0,0,0,0.08);border:1px solid #e2e8f0;position:relative;overflow:hidden;">
                        <div style="position:absolute;top:-15px;right:-15px;font-size:5rem;opacity:0.05;">🔧</div>
                        <div style="font-size:0.85rem;color:#718096;margin-bottom:0.5rem;font-weight:500;">Under Maintenance</div>
                        <div style="font-size:2.5rem;font-weight:800;color:#1a202c;">${underMaint}</div>
                        <div style="font-size:0.8rem;color:#a0aec0;margin-top:0.3rem;">Currently being serviced</div>
                    </div>
                    <div style="background:#fff;padding:1.75rem;border-radius:16px;color:#1a202c;box-shadow:0 2px 12px rgba(0,0,0,0.08);border:1px solid #e2e8f0;position:relative;overflow:hidden;">
                        <div style="position:absolute;top:-15px;right:-15px;font-size:5rem;opacity:0.05;">📅</div>
                        <div style="font-size:0.85rem;color:#718096;margin-bottom:0.5rem;font-weight:500;">PMS Due Soon</div>
                        <div style="font-size:2.5rem;font-weight:800;color:#1a202c;">${pmsDueSoon}</div>
                        <div style="font-size:0.8rem;color:#a0aec0;margin-top:0.3rem;">Within 14 days</div>
                    </div>
                    <div style="background:#fff;padding:1.75rem;border-radius:16px;color:#1a202c;box-shadow:0 2px 12px rgba(0,0,0,0.08);border:1px solid #e2e8f0;position:relative;overflow:hidden;">
                        <div style="position:absolute;top:-15px;right:-15px;font-size:5rem;opacity:0.05;">⚠️</div>
                        <div style="font-size:0.85rem;color:#718096;margin-bottom:0.5rem;font-weight:500;">PMS Overdue</div>
                        <div style="font-size:2.5rem;font-weight:800;color:#1a202c;">${pmsOverdue}</div>
                        <div style="font-size:0.8rem;color:#a0aec0;margin-top:0.3rem;">Needs immediate attention</div>
                    </div>`;
            }

            // Render vehicle cards
            const listEl = document.getElementById('customerVehiclesList');
            if (!listEl) return;

            if (myAssets.length === 0) {
                listEl.innerHTML = '<div style="color:#718096;padding:2rem;text-align:center;">No vehicles found for this account.</div>';
                return;
            }

            function getStatusLabel(asset) {
                if (asset.status === 'maintenance') return { label: '🔵 Under Maintenance', color: 'rgba(255,255,255,0.3)' };
                if (asset.status === 'inactive') return { label: '⚫ Inactive', color: 'rgba(255,255,255,0.2)' };
                if (asset.nextPMSDue) {
                    const due = new Date(asset.nextPMSDue);
                    due.setHours(0,0,0,0);
                    const diff = Math.ceil((due - today) / (1000*60*60*24));
                    if (diff < 0) return { label: '🔴 PMS Overdue', color: 'rgba(255,100,100,0.4)' };
                    if (diff <= 14) return { label: '🟡 PMS Due Soon', color: 'rgba(255,200,50,0.35)' };
                }
                return { label: '✅ Active', color: 'rgba(255,255,255,0.25)' };
            }

            listEl.innerHTML = myAssets.map(asset => {
                const statusInfo = getStatusLabel(asset);
                const lastSvc = asset.lastServiceDate
                    ? new Date(asset.lastServiceDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                    : '—';
                const nextPMS = asset.nextPMSDue
                    ? new Date(asset.nextPMSDue).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                    : '—';
                const odo = asset.odometer ? asset.odometer.toLocaleString() + ' km' : '—';

                // PMS date color
                let pmsColor = '#2c5282'; let pmsBg = 'linear-gradient(135deg,#ebf8ff 0%,#bee3f8 100%)'; let pmsBorder = '#4299e1';
                if (asset.nextPMSDue) {
                    const due = new Date(asset.nextPMSDue); due.setHours(0,0,0,0);
                    const diff = Math.ceil((due - today) / (1000*60*60*24));
                    if (diff < 0) { pmsColor='#742a2a'; pmsBg='linear-gradient(135deg,#fff5f5 0%,#fed7d7 100%)'; pmsBorder='#f56565'; }
                    else if (diff <= 14) { pmsColor='#7c2d12'; pmsBg='linear-gradient(135deg,#fff5e6 0%,#feebc8 100%)'; pmsBorder='#ed8936'; }
                }

                return `
                <div style="background:white;border-radius:20px;overflow:hidden;box-shadow:0 8px 30px rgba(0,0,0,0.1);border:1px solid #e2e8f0;transition:all 0.3s ease;" onmouseover="this.style.transform='translateY(-4px)';this.style.boxShadow='0 16px 40px rgba(0,0,0,0.15)';" onmouseout="this.style.transform='translateY(0)';this.style.boxShadow='0 8px 30px rgba(0,0,0,0.1)';">
                    <div style="background:#ffffff;padding:1.75rem;color:#1a202c;position:relative;overflow:hidden;border-bottom:1px solid #e2e8f0;">
                        <div style="position:absolute;top:-25px;right:-25px;font-size:9rem;opacity:0.04;">${asset.icon}</div>
                        <div style="display:flex;justify-content:space-between;align-items:start;position:relative;z-index:1;">
                            <div style="display:flex;align-items:center;gap:1rem;">
                                <div style="background:#f0f4ff;width:54px;height:54px;border-radius:14px;display:flex;align-items:center;justify-content:center;font-size:1.75rem;">${asset.icon}</div>
                                <div>
                                    <div style="font-size:1.2rem;font-weight:800;letter-spacing:-0.3px;color:#1a202c;">${asset.assetDescription}</div>
                                    <div style="font-size:0.95rem;color:#718096;margin-top:0.15rem;">${asset.plateNumber}</div>
                                </div>
                            </div>
                            <span style="background:${statusInfo.color};padding:0.4rem 0.9rem;border-radius:20px;font-size:0.78rem;font-weight:700;white-space:nowrap;">${statusInfo.label}</span>
                        </div>
                    </div>
                    <div style="padding:1.5rem;">
                        <div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin-bottom:1.5rem;">
                            <div style="background:linear-gradient(135deg,#f7fafc 0%,#edf2f7 100%);padding:1rem;border-radius:12px;border-left:4px solid #E31E24;">
                                <div style="font-size:0.75rem;color:#718096;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:0.3rem;">📏 Odometer</div>
                                <div style="font-size:1.2rem;font-weight:800;color:#1a202c;">${odo}</div>
                            </div>
                            <div style="background:linear-gradient(135deg,#f0fff4 0%,#c6f6d5 100%);padding:1rem;border-radius:12px;border-left:4px solid #48bb78;">
                                <div style="font-size:0.75rem;color:#22543d;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:0.3rem;">✅ Last Service</div>
                                <div style="font-size:1rem;font-weight:700;color:#22543d;">${lastSvc}</div>
                            </div>
                            <div style="background:${pmsBg};padding:1rem;border-radius:12px;border-left:4px solid ${pmsBorder};">
                                <div style="font-size:0.75rem;color:${pmsColor};font-weight:600;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:0.3rem;">📅 Next PMS</div>
                                <div style="font-size:1rem;font-weight:700;color:${pmsColor};">${nextPMS}</div>
                            </div>

                        </div>
                        <button class="btn-primary" style="width:100%;padding:0.9rem;font-weight:700;border-radius:12px;font-size:0.95rem;justify-content:center;" onclick="viewVehicleHistory('${asset.plateNumber}')">
                            📋 View Maintenance History
                        </button>
                    </div>
                </div>`;
            }).join('');
        }

        // Customer navigation
        document.querySelectorAll('#customerDashboard .admin-nav-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const section = e.target.closest('.admin-nav-btn').dataset.section;
                switchCustomerSection(section);
            });
        });

        function switchCustomerSection(sectionName) {
            const dashboard = document.getElementById('customerDashboard');
            dashboard.querySelectorAll('.admin-nav-btn').forEach(btn => btn.classList.remove('active'));
            dashboard.querySelector(`[data-section="${sectionName}"]`).classList.add('active');
            
            dashboard.querySelectorAll('.admin-section').forEach(section => section.classList.remove('active'));
            dashboard.querySelector(`#${sectionName}`).classList.add('active');
            
            const titles = {
                'customer-vehicles': 'My Vehicles',
                'customer-reminders': 'Smart Reports'
            };
            dashboard.querySelector('#customerSectionTitle').textContent = titles[sectionName] || 'Customer Portal';

            if (sectionName === 'customer-reminders') {
                updateCustomerSmartStats();
            }
        }

        function updateCustomerSmartStats() {
            const owner = currentUser ? currentUser.name : 'John Doe';
            const myAssets = assets.filter(a => a.owner === owner);
            const today = new Date(); today.setHours(0,0,0,0);

            const overdue = myAssets.filter(a => {
                if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                return new Date(a.nextPMSDue) < today;
            }).length;
            const dueSoon = myAssets.filter(a => {
                if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                const diff = Math.ceil((new Date(a.nextPMSDue) - today) / 86400000);
                return diff >= 0 && diff <= 14;
            }).length;
            const maint = myAssets.filter(a => a.status === 'maintenance').length;

            const s = id => document.getElementById(id);
            if (s('csrStatAssets')) s('csrStatAssets').textContent = myAssets.length;
            if (s('csrStatOverdue')) s('csrStatOverdue').textContent = overdue;
            if (s('csrStatDueSoon')) s('csrStatDueSoon').textContent = dueSoon;
            if (s('csrStatMaint')) s('csrStatMaint').textContent = maint;
        }

        function clearCustomerSmartChat() {
            const messages = document.getElementById('csrChatMessages');
            if (!messages) return;
            messages.innerHTML = `
                <div class="sr-welcome-bubble">
                    <div class="sr-avatar-ai">🤖</div>
                    <div class="sr-bubble-ai">
                        <div style="font-weight:700;margin-bottom:0.4rem;font-size:0.95rem;">Hello! I'm your Smart Reports assistant. 👋</div>
                        <div style="color:#4a5568;font-size:0.88rem;line-height:1.6;margin-bottom:1rem;">Ask me anything about your vehicles — PMS status, maintenance history, and more.</div>
                        <div class="sr-welcome-chips">
                            <button class="sr-suggest-chip" onclick="runCustomerSmartQuery('Show all my vehicles')">🚛 All my vehicles</button>
                            <button class="sr-suggest-chip" onclick="runCustomerSmartQuery('Which of my assets are under maintenance?')">🔵 Under maintenance</button>
                            <button class="sr-suggest-chip" onclick="runCustomerSmartQuery('Which of my assets have PMS overdue?')">⚠️ PMS overdue</button>
                            <button class="sr-suggest-chip" onclick="runCustomerSmartQuery('Which of my assets have PMS due soon?')">📅 PMS due soon</button>
                            <button class="sr-suggest-chip" onclick="runCustomerSmartQuery('Show maintenance history of my assets')">📋 Maintenance history</button>
                        </div>
                    </div>
                </div>`;
        }

        function runCustomerSmartQuery(queryText) {
            const input = document.getElementById('customerSmartQueryInput');
            const query = queryText || (input ? input.value.trim() : '');
            if (!query) return;

            const messages = document.getElementById('csrChatMessages');
            if (!messages) return;

            // User bubble
            const userRow = document.createElement('div');
            userRow.className = 'sr-msg-row sr-msg-user';
            userRow.innerHTML = `<div class="sr-bubble-user">${escapeHtml(query)}</div><div class="sr-avatar-user">👤</div>`;
            messages.appendChild(userRow);

            if (input) { input.value = ''; input.style.height = 'auto'; }

            // Typing indicator
            const typingId = 'csr_typing_' + Date.now();
            const typingRow = document.createElement('div');
            typingRow.className = 'sr-msg-row sr-msg-ai';
            typingRow.id = typingId;
            typingRow.innerHTML = `<div class="sr-avatar-ai">🤖</div><div class="sr-bubble-ai sr-typing"><span></span><span></span><span></span></div>`;
            messages.appendChild(typingRow);
            messages.scrollTop = messages.scrollHeight;

            setTimeout(() => {
                const el = document.getElementById(typingId);
                if (el) el.remove();
                const result = processCustomerSmartQuery(query);
                const aiRow = document.createElement('div');
                aiRow.className = 'sr-msg-row sr-msg-ai';
                aiRow.innerHTML = `<div class="sr-avatar-ai">🤖</div><div class="sr-bubble-ai">${buildCustomerResultHtml(result)}</div>`;
                messages.appendChild(aiRow);
                messages.scrollTop = messages.scrollHeight;
            }, 600);
        }

        function processCustomerSmartQuery(query) {
            const q = query.toLowerCase();
            const owner = currentUser ? currentUser.name : 'John Doe';
            const myAssets = assets.filter(a => a.owner === owner);
            const today = new Date(); today.setHours(0,0,0,0);

            // All vehicles
            if (q.includes('all my') || q.includes('show all') || q.includes('list') || q.includes('all vehicles')) {
                return {
                    type: 'blue', icon: '🚛', title: 'All My Vehicles',
                    body: `${myAssets.length} vehicle(s) registered under ${owner}.`,
                    rows: myAssets.map(a => ({ label: `${a.assetNum} – ${a.assetDescription}`, value: a.plateNumber }))
                };
            }
            // Under maintenance
            if (q.includes('under maintenance') || q.includes('maintenance')) {
                const list = myAssets.filter(a => a.status === 'maintenance');
                if (!list.length) return { type: 'success', icon: '✅', title: 'Under Maintenance', body: 'None of your vehicles are currently under maintenance.', rows: [] };
                return { type: 'blue', icon: '🔵', title: 'Vehicles Under Maintenance', body: `${list.length} vehicle(s) currently being serviced.`, rows: list.map(a => ({ label: `${a.assetNum} – ${a.assetDescription}`, value: a.plateNumber })) };
            }
            // PMS overdue
            if (q.includes('overdue')) {
                const list = myAssets.filter(a => {
                    if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                    return new Date(a.nextPMSDue) < today;
                });
                if (!list.length) return { type: 'success', icon: '✅', title: 'PMS Overdue', body: 'Great news! None of your vehicles are overdue for PMS.', rows: [] };
                return { type: 'danger', icon: '⚠️', title: 'Vehicles with PMS Overdue', body: `${list.length} vehicle(s) need immediate attention.`, rows: list.map(a => ({ label: `${a.assetNum} – ${a.assetDescription}`, value: `Due: ${new Date(a.nextPMSDue).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'})}` })) };
            }
            // PMS due soon
            if (q.includes('due soon') || q.includes('upcoming') || q.includes('pms')) {
                const list = myAssets.filter(a => {
                    if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                    const diff = Math.ceil((new Date(a.nextPMSDue) - today) / 86400000);
                    return diff >= 0 && diff <= 14;
                });
                if (!list.length) return { type: 'success', icon: '✅', title: 'PMS Due Soon', body: 'No vehicles have PMS due within the next 14 days.', rows: [] };
                return { type: 'warning', icon: '📅', title: 'Vehicles with PMS Due Soon', body: `${list.length} vehicle(s) have PMS due within 14 days.`, rows: list.map(a => ({ label: `${a.assetNum} – ${a.assetDescription}`, value: `Due: ${new Date(a.nextPMSDue).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'})}` })) };
            }
            // Maintenance history
            if (q.includes('history') || q.includes('service record') || q.includes('maintenance history')) {
                const rows = [];
                myAssets.forEach(a => {
                    (a.maintenanceHistory || []).forEach(h => {
                        rows.push({ label: `${a.assetNum} – ${h.service}`, value: new Date(h.date).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'}) });
                    });
                });
                rows.sort((a, b) => new Date(b.value) - new Date(a.value));
                if (!rows.length) return { type: 'info', icon: '📋', title: 'Maintenance History', body: 'No maintenance records found.', rows: [] };
                return { type: 'green', icon: '📋', title: 'Maintenance History', body: `${rows.length} service record(s) across all your vehicles.`, rows };
            }
            // Fallback
            return { type: 'info', icon: '🤔', title: 'No Matching Query', body: `Sorry, I couldn't understand "${query}". Try one of the suggestions above.`, rows: [] };
        }

        function buildCustomerResultHtml(result) {
            const colorMap = {
                danger:  { badge: '#fed7d7', badgeText: '#742a2a', header: '#e53e3e' },
                warning: { badge: '#fefcbf', badgeText: '#744210', header: '#d69e2e' },
                success: { badge: '#c6f6d5', badgeText: '#22543d', header: '#38a169' },
                green:   { badge: '#c6f6d5', badgeText: '#22543d', header: '#38a169' },
                blue:    { badge: '#bee3f8', badgeText: '#1a365d', header: '#3182ce' },
                info:    { badge: '#e2e8f0', badgeText: '#2d3748', header: '#718096' }
            };
            const c = colorMap[result.type] || colorMap.info;
            const tableHtml = result.rows.length > 0 ? `
                <div style="border-radius:10px;overflow:hidden;border:1px solid #e2e8f0;margin-top:1rem;">
                    <table style="width:100%;border-collapse:collapse;background:white;">
                        <thead><tr style="background:${c.header};">
                            <th style="padding:0.6rem 0.9rem;text-align:left;color:white;font-size:0.75rem;font-weight:700;text-transform:uppercase;width:36px;">#</th>
                            <th style="padding:0.6rem 0.9rem;text-align:left;color:white;font-size:0.75rem;font-weight:700;text-transform:uppercase;">Item</th>
                            <th style="padding:0.6rem 0.9rem;text-align:right;color:white;font-size:0.75rem;font-weight:700;text-transform:uppercase;">Value</th>
                        </tr></thead>
                        <tbody>${result.rows.map((r,i) => `
                            <tr style="background:${i%2===0?'#f9fafb':'white'};border-bottom:1px solid #e2e8f0;">
                                <td style="padding:0.65rem 0.9rem;color:#a0aec0;font-size:0.8rem;font-weight:600;">${i+1}</td>
                                <td style="padding:0.65rem 0.9rem;font-weight:600;color:#1a202c;font-size:0.88rem;">${r.label}</td>
                                <td style="padding:0.65rem 0.9rem;text-align:right;"><span style="background:${c.badge};color:${c.badgeText};padding:0.25rem 0.75rem;border-radius:20px;font-size:0.78rem;font-weight:700;">${r.value}</span></td>
                            </tr>`).join('')}
                        </tbody>
                    </table>
                </div>
                <div style="margin-top:0.5rem;font-size:0.75rem;color:#a0aec0;text-align:right;">${result.rows.length} result(s)</div>` : '';

            const followUp = `
                <div style="margin-top:1rem;padding-top:0.85rem;border-top:1px solid #e2e8f0;">
                    <div style="font-size:0.75rem;color:#a0aec0;font-weight:600;margin-bottom:0.5rem;text-transform:uppercase;letter-spacing:0.5px;">Try asking:</div>
                    <div style="display:flex;flex-wrap:wrap;gap:0.4rem;">
                        <button class="sr-suggest-chip" onclick="runCustomerSmartQuery('Show all my vehicles')">🚛 All vehicles</button>
                        <button class="sr-suggest-chip" onclick="runCustomerSmartQuery('Which of my assets have PMS overdue?')">⚠️ PMS overdue</button>
                        <button class="sr-suggest-chip" onclick="runCustomerSmartQuery('Which of my assets have PMS due soon?')">📅 Due soon</button>
                        <button class="sr-suggest-chip" onclick="runCustomerSmartQuery('Which of my assets are under maintenance?')">🔵 Under maintenance</button>
                    </div>
                </div>`;

            return `
                <div style="display:flex;align-items:center;gap:0.6rem;margin-bottom:0.5rem;">
                    <span style="font-size:1.3rem;">${result.icon}</span>
                    <div>
                        <div style="font-size:0.95rem;font-weight:800;color:#1a202c;">${result.title}</div>
                        <div style="font-size:0.83rem;color:#718096;margin-top:0.1rem;">${result.body}</div>
                    </div>
                </div>
                ${tableHtml}${followUp}`;
        }

        // Staff navigation
        document.querySelectorAll('#staffDashboard .admin-nav-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const section = e.target.closest('.admin-nav-btn').dataset.section;
                switchStaffSection(section);
            });
        });

        function switchStaffSection(sectionName) {
            const dashboard = document.getElementById('staffDashboard');
            dashboard.querySelectorAll('.admin-nav-btn').forEach(btn => btn.classList.remove('active'));
            dashboard.querySelector(`[data-section="${sectionName}"]`).classList.add('active');
            
            dashboard.querySelectorAll('.admin-section').forEach(section => section.classList.remove('active'));
            dashboard.querySelector(`#${sectionName}`).classList.add('active');
            
            const titles = {
                'staff-overview': 'Dashboard',
                'staff-inventory': 'Inventory Management',
                'staff-pms': 'PMS Monitoring'
            };
            dashboard.querySelector('#staffSectionTitle').textContent = titles[sectionName] || 'Staff Portal';
            
            // Load PMS data when switching to staff-pms section
            if (sectionName === 'staff-pms') {
                renderStaffPMSList();
            }
        }

        // Render assets list
        function renderAssetsList() {
                    const assetsList = document.getElementById('assetsList');
                    if (!assetsList) return;

                    if (assets.length === 0) {
                        assetsList.innerHTML = '<div class="table-row" style="text-align: center; color: #718096; padding: 2rem;">No assets found. Click "Add Asset" to create one.</div>';
                        return;
                    }

                    const today = new Date();
                    today.setHours(0, 0, 0, 0);

                    function getStatusBadge(asset) {
                        // Auto-reset completed → active after 1 day
                        if (asset.status === 'completed' && asset.completedAt) {
                            const completedDate = new Date(asset.completedAt);
                            completedDate.setHours(0, 0, 0, 0);
                            const diffDays = Math.ceil((today - completedDate) / (1000 * 60 * 60 * 24));
                            if (diffDays >= 1) {
                                asset.status = 'active';
                                asset.completedAt = null;
                            }
                        }

                        if (asset.status === 'inactive') {
                            return '<span class="status-badge status-completed">Inactive</span>';
                        }
                        if (asset.status === 'maintenance') {
                            return '<span class="status-badge" style="background:#bee3f8;color:#1a365d;border:1px solid #90cdf4;display:inline-flex;align-items:center;gap:0.35rem;padding:0.35rem 0.85rem;border-radius:20px;font-size:0.78rem;font-weight:700;white-space:nowrap;"><span style="width:7px;height:7px;border-radius:50%;background:#3182ce;box-shadow:0 0 0 2px rgba(49,130,206,0.25);flex-shrink:0;display:inline-block;"></span>Under Maintenance</span>';
                        }
                        if (asset.status === 'completed') {
                            return '<span class="status-badge status-completed">Completed</span>';
                        }
                        if (asset.nextPMSDue) {
                            const due = new Date(asset.nextPMSDue);
                            due.setHours(0, 0, 0, 0);
                            const diffDays = Math.ceil((due - today) / (1000 * 60 * 60 * 24));
                            if (diffDays < 0) {
                                return '<span class="status-badge status-overdue">PMS Overdue</span>';
                            }
                            if (diffDays <= 14) {
                                return '<span class="status-badge status-pending">PMS Due Soon</span>';
                            }
                        }
                        return '<span class="status-badge status-active">Active</span>';
                    }

                    const typeLabels = { car: 'Car', truck: 'Truck' };

                    assetsList.innerHTML = assets.map(asset => {
                        const typeLabel = typeLabels[asset.type] || asset.type || '-';
                        return `
                            <div class="table-row" style="grid-template-columns: 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 120px;">
                                <div><strong>${asset.assetNum}</strong></div>
                                <div>${asset.plateNumber}</div>
                                <div>${asset.icon} ${typeLabel}</div>
                                <div>${asset.owner}</div>
                                <div>${asset.odometer ? asset.odometer.toLocaleString() + ' km' : '-'}</div>
                                <div>${asset.lastServiceDate ? new Date(asset.lastServiceDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '-'}</div>
                                <div>${asset.nextPMSDue ? new Date(asset.nextPMSDue).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '-'}</div>
                                <div>${getStatusBadge(asset)}</div>
                                <div style="display:flex; gap:0.4rem; flex-wrap:nowrap;">
                                    <button class="btn-small btn-primary" onclick="viewAssetDetails('${asset.assetNum}')" title="View">👁️</button>
                                    <button class="btn-small btn-secondary" onclick="editAsset('${asset.assetNum}')" title="Edit">✏️</button>
                                    <button class="btn-small btn-danger" onclick="deleteAsset('${asset.assetNum}')" title="Delete">🗑️</button>
                                </div>
                            </div>
                        `;
                    }).join('');

                    updateDashboardStats();
                }


        // Update dashboard statistics
        function updateDashboardStats() {
            const totalAssets = assets.length;
            const pmsDue = assets.filter(a => a.status === 'pms_due').length;
            
            const totalAssetsEl = document.querySelector('#overview .stat-number');
            const pmsDueEl = document.querySelectorAll('#overview .stat-number')[1];
            
            if (totalAssetsEl) totalAssetsEl.textContent = totalAssets;
            if (pmsDueEl) pmsDueEl.textContent = pmsDue;
        }

        // Modal functions
        function populateAssetOwnerDropdown() {
            const select = document.getElementById('assetOwnerSelect');
            if (!select) return;
            const customers = [...new Set(assets.map(a => a.owner))];
            // Also include known accounts
            const allOwners = [...new Set([...customers, 'John Doe', 'Maria Santos'])];
            select.innerHTML = '<option value="">Select Owner (Customer)</option>' +
                allOwners.map(o => `<option value="${o}">${o}</option>`).join('');
        }

        function openAddAssetModal() {
            currentEditingAsset = null;
            document.getElementById('addAssetModal').classList.add('active');
            document.querySelector('#addAssetModal h2').textContent = 'Add New Asset';
            document.getElementById('addAssetForm').reset();
            // Auto-generate asset number
            document.getElementById('assetNumDisplay').value = 'ASSET-' + String(nextAssetId).padStart(3, '0');
            populateAssetOwnerDropdown();
        }

        function openServiceRecordModal() {
            document.getElementById('serviceRecordModal').classList.add('active');
        }

        function closeModal(modalId) {
            document.getElementById(modalId).classList.remove('active');
            // Only reset editing state when closing primary modals, not nested scan modals
            const scanModals = ['invScanModal', 'itemMasterScanModal', 'serviceScanModal',
                                'scanBarcodeModal', 'scanQRModal', 'scanPhysicalCountModal',
                                'staffScanModal', 'deliveryScanModal'];
            if (!scanModals.includes(modalId)) {
                currentEditingAsset = null;
            }
        }

        function viewVehicleHistory(plateNumber) {
            const asset = assets.find(a => a.plateNumber === plateNumber);
            if (!asset) return;

            document.getElementById('vehicleHistoryModal').classList.add('active');
            document.getElementById('historyVehiclePlate').textContent = plateNumber;
            document.getElementById('historyVehicleName').textContent = asset.model;

            const historyContent = document.querySelector('#vehicleHistoryContent .data-table');
            if (asset.maintenanceHistory.length === 0) {
                historyContent.innerHTML = '<div style="padding: 2rem; text-align: center; color: #718096;">No maintenance history available</div>';
            } else {
                historyContent.innerHTML = asset.maintenanceHistory.map(record => `
                    <div class="table-row">
                        <div>
                            <strong>${record.service}</strong><br>
                            <small style="color: #718096;">${new Date(record.date).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })}</small>
                        </div>
                        <div>
                            <div>Parts: ${record.parts}</div>
                            <div>KM: ${record.km.toLocaleString()}</div>
                        </div>
                        <div>
                            <div style="font-weight: bold; color: #38a169;">₱${record.cost.toLocaleString()}</div>
                        </div>
                    </div>
                `).join('');
            }
        }

        // View asset details with full information
        function viewAssetDetails(assetNum) {
            const asset = assets.find(a => a.assetNum === assetNum);
            if (!asset) return;

            const yearsInService = new Date().getFullYear() - new Date(asset.dateAcquired).getFullYear();
            const totalMaintenanceCost = asset.maintenanceHistory.reduce((sum, r) => sum + r.cost, 0);

            const statusStyles = {
                active:        { bg: '#c6f6d5', color: '#276749', label: 'Active' },
                pms_due:       { bg: '#fefcbf', color: '#744210', label: 'PMS Due Soon' },
                under_service: { bg: '#bee3f8', color: '#1a365d', label: 'Ongoing' },
                maintenance:   { bg: '#bee3f8', color: '#1a365d', label: 'Under Maintenance' },
                completed:     { bg: '#e2e8f0', color: '#2d3748', label: 'Completed' },
                inactive:      { bg: '#e2e8f0', color: '#2d3748', label: 'Inactive' }
            };

            // Auto-reset completed → active after 1 day
            if (asset.status === 'completed' && asset.completedAt) {
                const completedDate = new Date(asset.completedAt);
                completedDate.setHours(0, 0, 0, 0);
                const todayDate = new Date(); todayDate.setHours(0, 0, 0, 0);
                if (Math.ceil((todayDate - completedDate) / (1000 * 60 * 60 * 24)) >= 1) {
                    asset.status = 'active';
                    asset.completedAt = null;
                }
            }

            // Compute real status from PMS date if active
            let displayStatus = asset.status;
            if (asset.status === 'active' && asset.nextPMSDue) {
                const due = new Date(asset.nextPMSDue); due.setHours(0,0,0,0);
                const todayDate = new Date(); todayDate.setHours(0,0,0,0);
                const diff = Math.ceil((due - todayDate) / (1000 * 60 * 60 * 24));
                if (diff < 0) displayStatus = 'pms_overdue';
                else if (diff <= 14) displayStatus = 'pms_due';
            }

            const extendedStyles = {
                ...statusStyles,
                pms_overdue: { bg: '#fed7d7', color: '#742a2a', label: 'PMS Overdue' }
            };
            const st = extendedStyles[displayStatus] || statusStyles.active;

            // Header
            document.getElementById('adIcon').textContent = asset.icon || '🚗';
            document.getElementById('adAssetDesc').textContent = asset.assetDescription || asset.type;
            document.getElementById('adPlate').textContent = '🪪 ' + asset.plateNumber;
            document.getElementById('adAssetNum').textContent = asset.assetNum;
            document.getElementById('adStatusBadge').innerHTML =
                `<span style="display:inline-flex;align-items:center;gap:0.35rem;background:${st.bg};color:${st.color};padding:0.35rem 0.85rem;border-radius:20px;font-size:0.8rem;font-weight:700;"><span style="width:7px;height:7px;border-radius:50%;background:${st.color};flex-shrink:0;display:inline-block;"></span>${st.label}</span>`;

            // Stats
            document.getElementById('adOdometer').textContent = asset.odometer ? asset.odometer.toLocaleString() + ' km' : 'N/A';
            document.getElementById('adLastService').textContent = asset.lastServiceDate
                ? new Date(asset.lastServiceDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A';
            document.getElementById('adNextPMS').textContent = asset.nextPMSDue
                ? new Date(asset.nextPMSDue).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A';

            // Info grid — only fields from the asset form
            const infoItems = [
                { label: 'Owner',                   value: asset.owner || 'N/A' },
                { label: 'Asset Type',              value: asset.type ? asset.type.charAt(0).toUpperCase() + asset.type.slice(1) : 'N/A' },
                { label: 'Current Odometer',        value: asset.odometer ? asset.odometer.toLocaleString() + ' km' : 'N/A' },
                { label: 'Last Service Odometer',   value: asset.lastServiceOdometer ? asset.lastServiceOdometer.toLocaleString() + ' km' : 'N/A' },
                { label: 'Service Frequency',       value: asset.serviceFrequency ? 'Every ' + asset.serviceFrequency + ' month(s)' : 'N/A' },
                { label: 'Assigned Mechanic',       value: asset.assignedMechanic || 'None' },
            ];
            document.getElementById('adInfoGrid').innerHTML = infoItems.map(item => `
                <div style="background: #f7fafc; border-radius: 10px; padding: 0.85rem 1rem;">
                    <div style="font-size: 0.72rem; color: #718096; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; margin-bottom: 0.3rem;">${item.label}</div>
                    <div style="font-weight: 700; color: #1a202c; font-size: 0.92rem;">${item.value}</div>
                </div>
            `).join('');

            // Meters
            if (asset.meters && asset.meters.length > 0) {
                document.getElementById('adMetersSection').style.display = 'block';
                document.getElementById('adMetersGrid').innerHTML = asset.meters.map(m => `
                    <div style="background: #ebf8ff; border-radius: 10px; padding: 0.85rem 1rem; border-left: 3px solid #3182ce;">
                        <div style="font-size: 0.72rem; color: #2c5282; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; margin-bottom: 0.3rem;">${m.name}</div>
                        <div style="font-weight: 800; color: #2b6cb0; font-size: 1.1rem;">${parseFloat(m.value).toLocaleString()} <span style="font-size:0.75rem;font-weight:600;">${m.unit}</span></div>
                    </div>
                `).join('');
            } else {
                document.getElementById('adMetersSection').style.display = 'none';
            }

            // Maintenance summary
            document.getElementById('adTotalServices').textContent = asset.maintenanceHistory.length;
            document.getElementById('adTotalCost').textContent = '₱' + totalMaintenanceCost.toLocaleString();

            document.getElementById('assetDetailsModal').classList.add('active');
        }

        // Edit asset
        function editAsset(assetNum) {
            if (currentUser && currentUser.role === 'staff') {
                alert('?��? Staff can only add new assets, not edit existing ones.');
                return;
            }

            const asset = assets.find(a => a.assetNum === assetNum);
            if (!asset) return;

            currentEditingAsset = asset;
            populateAssetOwnerDropdown();

            const form = document.getElementById('addAssetForm');
            form.elements.assetNum.value = asset.assetNum;
            form.elements.plateNumber.value = asset.plateNumber;
            form.elements.assetDescription.value = asset.assetDescription || '';
            form.elements.assetType.value = asset.type;
            form.elements.ownerName.value = asset.owner;
            form.elements.currentOdometer.value = asset.odometer || '';
            form.elements.lastServiceOdometer.value = asset.lastServiceOdometer || '';
            if (form.elements.lastServiceDate) form.elements.lastServiceDate.value = asset.lastServiceDate || '';
            form.elements.serviceFrequency.value = asset.serviceFrequency || '';

            document.querySelector('#addAssetModal h2').textContent = 'Edit Asset';
            document.getElementById('addAssetModal').classList.add('active');
        }

        // Delete asset
        function deleteAsset(assetNum) {
            if (currentUser && currentUser.role === 'staff') {
                alert('?��? Staff cannot delete assets.');
                return;
            }

            const asset = assets.find(a => a.assetNum === assetNum);
            if (!asset) return;

            if (confirm(`?��? Are you sure you want to delete ${asset.assetNum} (${asset.assetDescription})?\n\nThis action cannot be undone and will remove all maintenance history.`)) {
                assets = assets.filter(a => a.assetNum !== assetNum);
                renderAssetsList();
                alert(`✅ Asset ${asset.assetNum} has been deleted successfully.`);
            }
        }

        // Form submissions
        document.getElementById('addAssetForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            
            const form = e.target;
            const typeLabels = {
                car: 'Car',
                truck: 'Truck',
            };

            const formData = {
                assetNum: form.elements.assetNum.value.trim().toUpperCase(),
                plateNumber: form.elements.plateNumber.value.trim().toUpperCase(),
                assetDescription: form.elements.assetDescription.value.trim() || typeLabels[form.elements.assetType.value] || form.elements.assetType.value,
                type: form.elements.assetType.value.trim().toLowerCase(),
                brand: '',
                model: '',
                yearModel: null,
                engineNo: '',
                chassisNo: '',
                dateAcquired: new Date().toISOString().split('T')[0],
                owner: form.elements.ownerName.value.trim(),
                odometer: parseInt(form.elements.currentOdometer.value) || 0,
                lastServiceOdometer: parseInt(form.elements.lastServiceOdometer.value) || null,
                lastServiceDate: form.elements.lastServiceDate ? form.elements.lastServiceDate.value || null : null,
                serviceFrequency: parseInt(form.elements.serviceFrequency.value) || null,
                status: 'active'
            };

            // Build default odometer meter from current odometer value
            const meters = [];
            if (formData.odometer) {
                meters.push({
                    name: 'Odometer',
                    type: 'continuous',
                    value: String(formData.odometer),
                    unit: 'km'
                });
            }

            // Determine icon based on type
            const typeIcons = {
                truck: '🚛',
                car: '🚗',
            };
            
            // Get icon or default to truck
            const icon = typeIcons[formData.type] || '🚗';

            if (currentEditingAsset) {
                // Update existing asset
                const asset = assets.find(a => a.assetNum === currentEditingAsset.assetNum);
                if (asset) {
                    const recalcNextPMS = (formData.lastServiceDate && formData.serviceFrequency)
                        ? (() => {
                            const d = new Date(formData.lastServiceDate);
                            d.setMonth(d.getMonth() + formData.serviceFrequency);
                            return d.toISOString().split('T')[0];
                        })()
                        : asset.nextPMSDue;
                    Object.assign(asset, {
                        ...formData,
                        icon: icon,
                        nextPMSDue: recalcNextPMS,
                        meters: meters
                    });

                    alert(`✅ Asset ${formData.assetNum} updated successfully!`);
                }
            } else {
                // Check if asset number already exists
                if (assets.find(a => a.assetNum === formData.assetNum)) {
                    alert('❌ An asset with this Asset Number already exists!');
                    return;
                }

                // Check if plate number already exists
                if (assets.find(a => a.plateNumber === formData.plateNumber)) {
                    alert('❌ An asset with this Plate Number already exists!');
                    return;
                }

                // Add new asset
                const newAsset = {
                    id: nextAssetId++,
                    ...formData,
                    icon: icon,
                    nextPMSDue: (formData.lastServiceDate && formData.serviceFrequency)
                        ? (() => {
                            const d = new Date(formData.lastServiceDate);
                            d.setMonth(d.getMonth() + formData.serviceFrequency);
                            return d.toISOString().split('T')[0];
                        })()
                        : null,
                    assignedMechanic: null,
                    image: null,
                    meters: meters,
                    maintenanceHistory: []
                };

                assets.push(newAsset);
                alert(`✅ Asset ${formData.assetNum} added successfully!`);
            }

            renderAssetsList();
            closeModal('addAssetModal');
            form.reset();
        });

        document.getElementById('serviceRecordForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            alert('✅ Service record saved successfully!');
            closeModal('serviceRecordModal');
            e.target.reset();
        });

        function createPMSTemplate() {
            alert('📋 Create PMS Template feature');
        }

        // Meter Readings Functions
        function renderMeterReadingsList() {
            const list = document.getElementById('meterReadingsList');
            if (!list) return;

            // Get all meters from all assets
            const allMeters = [];
            assets.forEach(asset => {
                if (asset.meters && asset.meters.length > 0) {
                    asset.meters.forEach(meter => {
                        allMeters.push({
                            assetNum: asset.assetNum,
                            assetDescription: asset.assetDescription,
                            meterName: meter.name,
                            meterType: meter.type,
                            currentValue: meter.value,
                            unit: meter.unit
                        });
                    });
                }
            });

            if (allMeters.length === 0) {
                list.innerHTML = '<div class="table-row" style="text-align: center; color: #718096; padding: 2rem;">No meters assigned to assets yet. Add meters when creating or editing assets.</div>';
                return;
            }

            list.innerHTML = allMeters.map(meter => `
                <div class="table-row">
                    <div><strong>${meter.assetNum}</strong></div>
                    <div style="font-size: 0.85rem; color: #4a5568;">${meter.assetDescription}</div>
                    <div>${meter.meterName}</div>
                    <div><span style="background: #ebf8ff; color: #2c5282; padding: 0.2rem 0.6rem; border-radius: 4px; font-size: 0.8rem;">${meter.meterType}</span></div>
                    <div><strong>${meter.currentValue} ${meter.unit}</strong></div>
                    <div>
                        <button class="btn-small btn-primary" onclick="openUpdateMeterModal('${meter.assetNum}', '${meter.meterName}')" title="Update Reading">?��?</button>
                        <button class="btn-small btn-secondary" onclick="viewMeterHistory('${meter.assetNum}', '${meter.meterName}')" title="View History">��?</button>
                    </div>
                </div>
            `).join('');
        }

        function openAddMeterReadingModal() {
            document.getElementById('addMeterReadingModal').classList.add('active');
            
            // Populate asset dropdown with only assets that have meters
            const assetSelect = document.getElementById('meterAssetSelect');
            const assetsWithMeters = assets.filter(a => a.meters && a.meters.length > 0);
            
            if (assetsWithMeters.length === 0) {
                assetSelect.innerHTML = '<option value="">No assets with meters available</option>';
                alert('?��? No assets have meters assigned yet. Please add meters to assets first.');
                closeModal('addMeterReadingModal');
                return;
            }
            
            assetSelect.innerHTML = '<option value="">Select Asset</option>' + 
                assetsWithMeters.map(asset => `<option value="${asset.assetNum}">${asset.assetNum} - ${asset.assetDescription}</option>`).join('');
            
            // Set default date to today
            const dateInput = document.querySelector('[name="dateRecorded"]');
            dateInput.value = new Date().toISOString().split('T')[0];
            
            // Reset form
            document.getElementById('addMeterReadingForm').reset();
            document.getElementById('meterNameSelect').innerHTML = '<option value="">Select Meter</option>';
            document.getElementById('previousReading').value = '';
        }

        function openUpdateMeterModal(assetNum, meterName) {
            document.getElementById('addMeterReadingModal').classList.add('active');
            
            // Populate asset dropdown
            const assetSelect = document.getElementById('meterAssetSelect');
            assetSelect.innerHTML = '<option value="">Select Asset</option>' + 
                assets.filter(a => a.meters && a.meters.length > 0).map(asset => `<option value="${asset.assetNum}">${asset.assetNum} - ${asset.assetDescription}</option>`).join('');
            
            // Set the selected asset
            assetSelect.value = assetNum;
            
            // Load meters for this asset
            loadAssetMeters();
            
            // Set the selected meter
            setTimeout(() => {
                document.getElementById('meterNameSelect').value = meterName;
                loadPreviousReading();
            }, 100);
            
            // Set default date to today
            const dateInput = document.querySelector('[name="dateRecorded"]');
            dateInput.value = new Date().toISOString().split('T')[0];
        }

        function viewMeterHistory(assetNum, meterName) {
            const asset = assets.find(a => a.assetNum === assetNum);
            if (!asset) return;

            const meter = asset.meters.find(m => m.name === meterName);
            if (!meter) return;

            // Get all readings for this meter
            const readings = meterReadings.filter(r => r.assetNum === assetNum && r.meterName === meterName);

            let historyText = `📊 METER HISTORY\n\n`;
            historyText += `Asset: ${assetNum} - ${asset.assetDescription}\n`;
            historyText += `Meter: ${meterName}\n`;
            historyText += `Type: ${meter.type}\n`;
            historyText += `Current Value: ${meter.value} ${meter.unit}\n\n`;

            if (readings.length === 0) {
                historyText += `No reading history available yet.`;
            } else {
                historyText += `READING HISTORY:\n`;
                historyText += `?��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??�\n\n`;
                readings.sort((a, b) => new Date(b.dateRecorded) - new Date(a.dateRecorded)).forEach(reading => {
                    historyText += `Date: ${new Date(reading.dateRecorded).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}\n`;
                    historyText += `Previous: ${reading.previousReading}\n`;
                    historyText += `New: ${reading.newReading}\n`;
                    historyText += `Recorded By: ${reading.recordedBy}\n\n`;
                });
            }

            alert(historyText);
        }

        function loadAssetMeters() {
            const assetNum = document.getElementById('meterAssetSelect').value;
            const meterSelect = document.getElementById('meterNameSelect');
            
            if (!assetNum) {
                meterSelect.innerHTML = '<option value="">Select Meter</option>';
                document.getElementById('previousReading').value = '';
                return;
            }

            const asset = assets.find(a => a.assetNum === assetNum);
            if (!asset || !asset.meters || asset.meters.length === 0) {
                meterSelect.innerHTML = '<option value="">No meters available</option>';
                document.getElementById('previousReading').value = '';
                return;
            }

            meterSelect.innerHTML = '<option value="">Select Meter</option>' +
                asset.meters.map(meter => `<option value="${meter.name}">${meter.name} (${meter.unit})</option>`).join('');
        }

        function loadPreviousReading() {
            const assetNum = document.getElementById('meterAssetSelect').value;
            const meterName = document.getElementById('meterNameSelect').value;
            
            if (!assetNum || !meterName) {
                document.getElementById('previousReading').value = '';
                return;
            }

            const asset = assets.find(a => a.assetNum === assetNum);
            if (!asset || !asset.meters) {
                document.getElementById('previousReading').value = '';
                return;
            }

            const meter = asset.meters.find(m => m.name === meterName);
            if (meter) {
                document.getElementById('previousReading').value = `${meter.value} ${meter.unit}`;
            }
        }

        function viewMeterReading(id) {
            const reading = meterReadings.find(r => r.id === id);
            if (!reading) return;

            alert(`📋 METER READING DETAILS\n\n` +
                  `Asset Number: ${reading.assetNum}\n` +
                  `Meter Name: ${reading.meterName}\n` +
                  `Previous Reading: ${reading.previousReading}\n` +
                  `New Reading: ${reading.newReading}\n` +
                  `Date Recorded: ${new Date(reading.dateRecorded).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}\n` +
                  `Recorded By: ${reading.recordedBy}`);
        }

        function deleteMeterReading(id) {
            const reading = meterReadings.find(r => r.id === id);
            if (!reading) return;

            if (confirm(`?��? Are you sure you want to delete this meter reading?\n\nAsset: ${reading.assetNum}\nMeter: ${reading.meterName}\nDate: ${new Date(reading.dateRecorded).toLocaleDateString()}`)) {
                meterReadings = meterReadings.filter(r => r.id !== id);
                renderMeterReadingsList();
                alert('✅ Meter reading deleted successfully.');
            }
        }

        // Meter Reading Form Submission
        document.getElementById('addMeterReadingForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            
            const form = e.target;
            const assetNum = form.elements.assetNum.value;
            const meterName = form.elements.meterName.value;
            const newReading = parseFloat(form.elements.newReading.value);
            const dateRecorded = form.elements.dateRecorded.value;
            const previousReading = document.getElementById('previousReading').value;

            // Update the meter value in the asset
            const asset = assets.find(a => a.assetNum === assetNum);
            if (asset && asset.meters) {
                const meter = asset.meters.find(m => m.name === meterName);
                if (meter) {
                    meter.value = newReading.toString();
                }
            }

            // Add meter reading record
            const newMeterReading = {
                id: nextMeterReadingId++,
                assetNum: assetNum,
                meterName: meterName,
                previousReading: previousReading,
                newReading: newReading,
                dateRecorded: dateRecorded,
                recordedBy: currentUser ? currentUser.name : 'Unknown'
            };

            meterReadings.push(newMeterReading);
            renderMeterReadingsList();
            closeModal('addMeterReadingModal');
            form.reset();

            alert(`✅ Meter reading updated successfully!\n\nAsset: ${assetNum}\nMeter: ${meterName}\nNew Reading: ${newReading}`);
        });

        // Meter search functionality
        document.getElementById('meterSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#meterReadingsList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        // Asset Servicing Functions
        function calculateTotalCost() {
            let total = 0;

            document.querySelectorAll('#serviceRowsContainer .svc-cost').forEach(input => {
                total += parseFloat(input.value) || 0;
            });
            document.querySelectorAll('#materialRowsContainer .mat-cost').forEach(input => {
                total += parseFloat(input.value) || 0;
            });

            document.getElementById('totalCostDisplay').textContent = '₱' + total.toLocaleString('en-PH', {minimumFractionDigits: 2});
            return total;
        }

        function renderServicesList() {
            const list = document.getElementById('servicesList');
            if (!list) return;

            if (serviceTransactions.length === 0) {
                list.innerHTML = '<div class="table-row" style="text-align: center; color: #718096; padding: 2rem;">No service transactions recorded yet. Click "New Service" to create one.</div>';
                updateServiceStats();
                return;
            }

            const statusBadges = {
                pending:  '<span style="background:#fefcbf;color:#744210;padding:0.2rem 0.6rem;border-radius:12px;font-size:0.8rem;font-weight:600;">Pending</span>',
                ongoing:  '<span style="background:#bee3f8;color:#1a365d;border:1px solid #90cdf4;display:inline-flex;align-items:center;gap:0.35rem;padding:0.35rem 0.75rem;border-radius:20px;font-size:0.78rem;font-weight:700;"><span style="width:7px;height:7px;border-radius:50%;background:#3182ce;box-shadow:0 0 0 2px rgba(49,130,206,0.25);flex-shrink:0;display:inline-block;"></span>Ongoing</span>',
                complete: '<span style="background:#e2e8f0;color:#2d3748;border:1px solid #cbd5e0;display:inline-flex;align-items:center;gap:0.35rem;padding:0.35rem 0.75rem;border-radius:20px;font-size:0.78rem;font-weight:700;"><span style="width:7px;height:7px;border-radius:50%;background:#718096;box-shadow:0 0 0 2px rgba(113,128,150,0.25);flex-shrink:0;display:inline-block;"></span>Completed</span>'
            };

            list.innerHTML = serviceTransactions.map(service => {
                const badge = statusBadges[service.status] || statusBadges.pending;

                // Build action buttons based on status
                let actionBtns = `<button class="btn-small btn-primary" onclick="viewServiceDetails('${service.serviceId}')" title="View">👁️</button>`;
                actionBtns += `<button class="btn-small btn-secondary" onclick="editService('${service.serviceId}')" title="Edit">✏️</button>`;

                if (service.status === 'pending') {
                    actionBtns += `<button class="btn-small btn-success" onclick="approveService('${service.serviceId}')" title="Approve">✅</button>`;
                } else if (service.status === 'ongoing') {
                    actionBtns += `<button class="btn-small btn-success" onclick="completeService('${service.serviceId}')" title="Mark Complete">🏁</button>`;
                }

                actionBtns += `<button class="btn-small btn-danger" onclick="deleteService('${service.serviceId}')" title="Delete">🗑️</button>`;

                return `
                    <div class="table-row" style="grid-template-columns: 1fr 1fr 1.5fr 1fr 1fr 1fr 160px;">
                        <div>${new Date(service.dateServiced).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}</div>
                        <div><strong>${service.assetNum}</strong></div>
                        <div style="font-size: 0.85rem; color: #4a5568;">${service.assetDescription || '-'}</div>
                        <div>${service.mechanicName || '-'}</div>
                        <div><strong>₱${parseFloat(service.totalCost).toLocaleString('en-PH', {minimumFractionDigits: 2})}</strong></div>
                        <div>${badge}</div>
                        <div style="display:flex; gap:0.3rem; flex-wrap:wrap;">${actionBtns}</div>
                    </div>
                `;
            }).join('');

            updateServiceStats();
        }

        function approveService(serviceId) {
            const service = serviceTransactions.find(s => s.serviceId === serviceId);
            if (!service || service.status !== 'pending') return;
            if (!confirm(`Approve service ${serviceId} and set to Ongoing?`)) return;
            service.status = 'ongoing';
            renderServicesList();
            if (typeof renderStaffServicesList === 'function') renderStaffServicesList();
        }

        function completeService(serviceId) {
            const service = serviceTransactions.find(s => s.serviceId === serviceId);
            if (!service || service.status !== 'ongoing') return;
            if (!confirm(`Mark service ${serviceId} as Completed?`)) return;
            service.status = 'complete';

            // Auto-update asset last service date and next PMS due
            const asset = assets.find(a => a.assetNum === service.assetNum);
            if (asset && service.dateServiced) {
                const newDate = service.dateServiced;
                if (!asset.lastServiceDate || newDate >= asset.lastServiceDate) {
                    asset.lastServiceDate = newDate;
                    if (asset.serviceFrequency) {
                        const d = new Date(newDate);
                        d.setMonth(d.getMonth() + asset.serviceFrequency);
                        asset.nextPMSDue = d.toISOString().split('T')[0];
                    }
                }
                // Mark asset as completed; auto-resets to active after 1 day
                asset.status = 'completed';
                asset.completedAt = new Date().toISOString().split('T')[0];
            }

            createIssuancesFromService(service);
            renderServicesList();
            if (typeof renderStaffServicesList === 'function') renderStaffServicesList();
            renderAssetsList();
            if (typeof renderStaffAssetsList === 'function') renderStaffAssetsList();
            if (typeof generatePMSSchedules === 'function') generatePMSSchedules();
            alert(`✅ Service ${serviceId} marked as completed!`);
        }

        function updateServiceStats() {
            const s = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
            s('totalServices', serviceTransactions.length);
            s('ongoingServices', serviceTransactions.filter(s => s.status === 'ongoing').length);
            s('completedServices', serviceTransactions.filter(s => s.status === 'complete').length);
            s('pendingServices', serviceTransactions.filter(s => s.status === 'pending').length);
        }

        function getUOMOptions() {
            const uomDomain = domains.find(d => d.id === 'UOM');
            const list = uomDomain ? uomDomain.list : ['Each', 'Set', 'Hour', 'Piece', 'Litres', 'Gallon'];
            return list.map(v => `<option value="${v}">${v}</option>`).join('');
        }

        function getServiceItemOptions() {
            const serviceItems = itemMaster.filter(i => i.itemType === 'Service' || (i.commodityGroup || '').toLowerCase() === 'autoservice');
            return serviceItems.map(i => `<option value="${i.itemName}" data-uom="${i.uom || ''}" data-cost="${i.cost || 0}">${i.itemName}</option>`).join('');
        }

        function onServiceItemChange(select) {
            const row = select.closest('.service-row');
            const opt = select.options[select.selectedIndex];
            const uom = opt ? (opt.dataset.uom || '') : '';
            const unitCost = opt ? parseFloat(opt.dataset.cost || 0) : 0;
            const qty = parseFloat(row.querySelector('.svc-qty').value) || 1;
            row.querySelector('.svc-uom').value = uom;
            row.querySelector('.svc-cost').value = unitCost > 0 ? (qty * unitCost).toFixed(2) : '';
            calculateTotalCost();
        }

        function onServiceQtyChange(input) {
            const row = input.closest('.service-row');
            const opt = row.querySelector('.svc-item').options[row.querySelector('.svc-item').selectedIndex];
            const unitCost = opt ? parseFloat(opt.dataset.cost || 0) : 0;
            const qty = parseFloat(input.value) || 0;
            row.querySelector('.svc-cost').value = qty > 0 && unitCost > 0 ? (qty * unitCost).toFixed(2) : '';
            calculateTotalCost();
        }

        function addServiceRow(desc = '', qty = '', uom = '', cost = '') {
            const container = document.getElementById('serviceRowsContainer');
            const row = document.createElement('div');
            row.className = 'service-row';
            row.style.cssText = 'display:grid;grid-template-columns:minmax(0,3fr) 70px minmax(0,1fr) 90px 32px;gap:0.4rem;margin-bottom:0.5rem;align-items:center;';
            row.innerHTML = `
                <select class="svc-item" style="padding:0.5rem;border:1px solid #e2e8f0;border-radius:6px;font-size:0.9rem;min-width:0;overflow:hidden;text-overflow:ellipsis;" onchange="onServiceItemChange(this)">
                    <option value="">Select Service Item</option>
                    ${getServiceItemOptions()}
                </select>
                <input type="number" class="svc-qty" placeholder="1" min="0" step="1" value="${qty}" style="padding:0.5rem;border:1px solid #e2e8f0;border-radius:6px;font-size:0.9rem;width:100%;box-sizing:border-box;" oninput="onServiceQtyChange(this)">
                <select class="svc-uom" style="padding:0.5rem;border:1px solid #e2e8f0;border-radius:6px;font-size:0.9rem;min-width:0;">
                    <option value="">UOM</option>
                    ${getUOMOptions()}
                </select>
                <input type="number" class="svc-cost" placeholder="0.00" step="0.01" min="0" value="${cost}" style="padding:0.5rem;border:1px solid #e2e8f0;border-radius:6px;font-size:0.9rem;background:#f7fafc;width:100%;box-sizing:border-box;" readonly>
                <button type="button" onclick="this.closest('.service-row').remove();calculateTotalCost();" style="background:#fed7d7;border:none;border-radius:6px;color:#c53030;cursor:pointer;font-size:1rem;width:32px;height:32px;flex-shrink:0;">×</button>
            `;
            if (desc) {
                const sel = row.querySelector('.svc-item');
                sel.value = desc;
                onServiceItemChange(sel);
            }
            if (uom) row.querySelector('.svc-uom').value = uom;
            container.appendChild(row);
        }

        function addMaterialRow(itemNum = '', qty = '', uom = '', cost = '') {
            const container = document.getElementById('materialRowsContainer');
            const row = document.createElement('div');
            row.className = 'material-row';
            row.style.cssText = 'display:grid;grid-template-columns:minmax(0,3fr) 70px minmax(0,1fr) 90px 32px 32px;gap:0.4rem;margin-bottom:0.5rem;align-items:center;';
            row.innerHTML = `
                <select class="mat-item" style="padding:0.5rem;border:1px solid #e2e8f0;border-radius:6px;font-size:0.9rem;min-width:0;overflow:hidden;text-overflow:ellipsis;" onchange="onMaterialItemChange(this)">
                    <option value="">Select Item</option>
                    ${inventory.map(i => `<option value="${i.itemNum}" data-uom="${i.unit}" data-cost="${i.price}" data-stock="${i.stock}">${i.itemName}</option>`).join('')}
                </select>
                <input type="number" class="mat-qty" placeholder="1" min="1" step="1" value="${qty}" style="padding:0.5rem;border:1px solid #e2e8f0;border-radius:6px;font-size:0.9rem;width:100%;box-sizing:border-box;" oninput="onMaterialQtyChange(this)">
                <input type="text" class="mat-uom" placeholder="UOM" readonly value="${uom}" style="padding:0.5rem;border:1px solid #e2e8f0;border-radius:6px;font-size:0.9rem;background:#f7fafc;min-width:0;">
                <input type="number" class="mat-cost" placeholder="0.00" step="0.01" readonly value="${cost}" style="padding:0.5rem;border:1px solid #e2e8f0;border-radius:6px;font-size:0.9rem;background:#f7fafc;width:100%;box-sizing:border-box;">
                <button type="button" title="Scan or search item" onclick="openMatItemScanModal(this.closest('.material-row'))" style="background:#ebf8ff;border:1px solid #bee3f8;border-radius:6px;color:#2b6cb0;cursor:pointer;font-size:0.85rem;width:32px;height:32px;flex-shrink:0;display:flex;align-items:center;justify-content:center;">📷</button>
                <button type="button" onclick="this.closest('.material-row').remove();calculateTotalCost();" style="background:#fed7d7;border:none;border-radius:6px;color:#c53030;cursor:pointer;font-size:1rem;width:32px;height:32px;flex-shrink:0;">×</button>
            `;
            if (itemNum) {
                const sel = row.querySelector('.mat-item');
                sel.value = itemNum;
                onMaterialItemChange(sel);
                if (qty) row.querySelector('.mat-qty').value = qty;
                onMaterialQtyChange(row.querySelector('.mat-qty'));
            }
            container.appendChild(row);
        }

        // ── Material row scan/search modal ──────────────────────────────────
        let _matScanTargetRow = null;

        let _matScanSelectedItem = null;

        window.openMatItemScanModal = function (row) {
            _matScanTargetRow = row;
            _matScanSelectedItem = null;
            document.getElementById('matScanInput').value = '';
            document.getElementById('matScanResults').innerHTML = '';
            document.getElementById('matScanItemDetail').style.display = 'none';
            document.getElementById('matScanModal').classList.add('active');
            setTimeout(() => document.getElementById('matScanInput').focus(), 100);
        };

        window.searchMatScanItem = function () {
            const query = document.getElementById('matScanInput').value.trim().toLowerCase();
            const resultsEl = document.getElementById('matScanResults');
            // hide detail panel when searching again
            document.getElementById('matScanItemDetail').style.display = 'none';
            _matScanSelectedItem = null;

            if (!query) { resultsEl.innerHTML = '<div style="color:#718096;text-align:center;padding:1rem;">Enter a name, item number, or barcode.</div>'; return; }

            const matches = inventory.filter(i =>
                i.itemNum.toLowerCase().includes(query) ||
                i.itemName.toLowerCase().includes(query) ||
                (i.barcode && i.barcode.toLowerCase().includes(query)) ||
                (i.qrCode && i.qrCode.toLowerCase().includes(query))
            );

            if (matches.length === 0) {
                resultsEl.innerHTML = '<div style="color:#c53030;text-align:center;padding:1rem;">No items found.</div>';
                return;
            }

            resultsEl.innerHTML = matches.map(i => {
                const stockColor = i.status === 'out_of_stock' ? '#c53030' : i.status === 'low_stock' ? '#c05621' : '#276749';
                return `<div onclick="previewMatScanItem('${i.itemNum}')" style="display:flex;justify-content:space-between;align-items:center;padding:0.75rem 1rem;border-radius:8px;cursor:pointer;border:1px solid #e2e8f0;margin-bottom:0.4rem;background:white;transition:background 0.15s;" onmouseover="this.style.background='#ebf8ff'" onmouseout="this.style.background='white'">
                    <div>
                        <div style="font-weight:700;color:#1a202c;font-size:0.9rem;">${i.itemName}</div>
                        <div style="font-size:0.78rem;color:#718096;">${i.itemNum} · ${i.commodityGroup || ''}</div>
                    </div>
                    <div style="text-align:right;flex-shrink:0;margin-left:1rem;">
                        <div style="font-weight:700;color:${stockColor};font-size:0.9rem;">${i.stock} ${i.unit}</div>
                        <div style="font-size:0.75rem;color:#718096;">in stock</div>
                    </div>
                </div>`;
            }).join('');
        };

        window.previewMatScanItem = function (itemNum) {
            const item = inventory.find(i => i.itemNum === itemNum);
            if (!item) return;
            _matScanSelectedItem = item;

            // hide results, show detail panel
            document.getElementById('matScanResults').innerHTML = '';
            const detail = document.getElementById('matScanItemDetail');
            detail.style.display = 'block';

            const stockColor = item.status === 'out_of_stock' ? '#c53030' : item.status === 'low_stock' ? '#c05621' : '#276749';
            const stockLabel = item.status === 'out_of_stock' ? 'Out of Stock' : item.status === 'low_stock' ? 'Low Stock' : 'In Stock';

            document.getElementById('matScanDetailName').textContent = item.itemName;
            document.getElementById('matScanDetailNum').textContent = item.itemNum + (item.commodityGroup ? ' · ' + item.commodityGroup : '');
            document.getElementById('matScanDetailStock').innerHTML = `<span style="font-weight:800;color:${stockColor};font-size:1.1rem;">${item.stock} ${item.unit}</span> <span style="font-size:0.78rem;color:${stockColor};background:${item.status==='in_stock'?'#f0fff4':item.status==='low_stock'?'#fffaf0':'#fff5f5'};padding:0.15rem 0.5rem;border-radius:10px;font-weight:600;">${stockLabel}</span>`;
            document.getElementById('matScanDetailUOM').value = item.unit || '';
            document.getElementById('matScanDetailCost').value = '';
            document.getElementById('matScanDetailQty').value = '';
            document.getElementById('matScanDetailQty').max = item.stock;
            document.getElementById('matScanDetailUnitPrice').textContent = '₱' + parseFloat(item.price || 0).toLocaleString('en-PH', { minimumFractionDigits: 2 });
        };

        window.onMatScanQtyInput = function () {
            if (!_matScanSelectedItem) return;
            const stock = _matScanSelectedItem.stock || 0;
            const unitCost = parseFloat(_matScanSelectedItem.price || 0);
            const qtyInput = document.getElementById('matScanDetailQty');
            const warn = document.getElementById('matScanQtyWarn');
            let qty = parseFloat(qtyInput.value) || 0;

            if (qty > stock) {
                qty = stock;
                qtyInput.value = stock;
                qtyInput.style.borderColor = '#e53e3e';
                if (warn) { warn.style.display = 'block'; warn.textContent = '⚠️ Only ' + stock + ' ' + (_matScanSelectedItem.unit || '') + ' available. Quantity capped.'; }
            } else {
                qtyInput.style.borderColor = qty > 0 ? '#4299e1' : '#e2e8f0';
                if (warn) warn.style.display = 'none';
            }

            document.getElementById('matScanDetailCost').value = qty > 0 ? (qty * unitCost).toFixed(2) : '';
        };

        window.confirmMatScanItem = function () {
            if (!_matScanTargetRow || !_matScanSelectedItem) return;
            const qty = parseFloat(document.getElementById('matScanDetailQty').value) || 0;
            if (qty <= 0) { alert('Please enter a valid quantity.'); return; }
            if (qty > _matScanSelectedItem.stock) { alert('Quantity exceeds available stock (' + _matScanSelectedItem.stock + ' ' + _matScanSelectedItem.unit + ').'); return; }

            const sel = _matScanTargetRow.querySelector('.mat-item');
            sel.value = _matScanSelectedItem.itemNum;
            onMaterialItemChange(sel);
            // override qty after onMaterialItemChange sets it
            const qtyInput = _matScanTargetRow.querySelector('.mat-qty');
            qtyInput.value = qty;
            onMaterialQtyChange(qtyInput);

            closeModal('matScanModal');
            _matScanTargetRow = null;
            _matScanSelectedItem = null;
        };

        window.backToMatScanSearch = function () {
            document.getElementById('matScanItemDetail').style.display = 'none';
            _matScanSelectedItem = null;
            document.getElementById('matScanInput').focus();
        };

        // Allow pressing Enter in scan input
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Enter' && document.getElementById('matScanModal') && document.getElementById('matScanModal').classList.contains('active')) {
                e.preventDefault();
                searchMatScanItem();
            }
        });

        function onMaterialItemChange(select) {
            const row = select.closest('.material-row');
            const opt = select.options[select.selectedIndex];
            const uom = opt ? (opt.dataset.uom || '') : '';
            const unitCost = opt ? parseFloat(opt.dataset.cost || 0) : 0;
            const stock = opt ? parseInt(opt.dataset.stock || 0) : 0;
            const qtyInput = row.querySelector('.mat-qty');
            const qty = parseFloat(qtyInput.value) || 0;

            // Set max to available stock
            qtyInput.max = stock;
            qtyInput.style.borderColor = '#e2e8f0';

            // Remove any existing stock warning
            const existing = row.nextElementSibling;
            if (existing && existing.classList.contains('mat-stock-warning')) existing.remove();

            row.querySelector('.mat-uom').value = uom;
            row.querySelector('.mat-cost').value = qty > 0 ? (qty * unitCost).toFixed(2) : '';
            calculateTotalCost();
        }

        function onMaterialQtyChange(input) {
            const row = input.closest('.material-row');
            const opt = row.querySelector('.mat-item').options[row.querySelector('.mat-item').selectedIndex];
            const unitCost = opt ? parseFloat(opt.dataset.cost || 0) : 0;
            const stock = opt ? parseInt(opt.dataset.stock || 0) : Infinity;
            let qty = parseFloat(input.value) || 0;

            // Remove existing warning
            const existing = row.nextElementSibling;
            if (existing && existing.classList.contains('mat-stock-warning')) existing.remove();

            if (qty > stock) {
                // Clamp to max stock
                input.value = stock;
                qty = stock;
                input.style.borderColor = '#e53e3e';

                // Insert warning below the row
                const warn = document.createElement('div');
                warn.className = 'mat-stock-warning';
                warn.style.cssText = 'grid-column:1/-1;background:#fff5f5;border-left:3px solid #e53e3e;color:#c53030;font-size:0.8rem;padding:0.4rem 0.75rem;border-radius:4px;margin-bottom:0.4rem;';
                warn.textContent = `⚠️ Only ${stock} unit(s) available in stock. Quantity capped.`;
                row.insertAdjacentElement('afterend', warn);
            } else {
                input.style.borderColor = '#e2e8f0';
            }

            row.querySelector('.mat-cost').value = qty > 0 && unitCost > 0 ? (qty * unitCost).toFixed(2) : '';
            calculateTotalCost();
        }

        function openAddServiceModal() {
            document.getElementById('addServiceModal').classList.add('active');
            document.getElementById('serviceModalTitle').textContent = 'New Service Transaction';
            document.getElementById('addServiceForm').reset();
            document.getElementById('servicePlateSearch').value = '';
            document.getElementById('serviceAssetNumDisplay').value = '';
            document.getElementById('serviceAssetNumHidden').value = '';
            document.getElementById('serviceAssetTypeDisplay').value = '';
            document.getElementById('serviceAssetDescription').value = '';
            document.getElementById('plateSuggestions').style.display = 'none';
            document.getElementById('totalCostDisplay').textContent = '₱0.00';
            document.querySelector('[name="dateServiced"]').value = new Date().toISOString().split('T')[0];
            document.getElementById('serviceMechanicName').value = '';

            // Reset rows
            document.getElementById('serviceRowsContainer').innerHTML = '';
            document.getElementById('materialRowsContainer').innerHTML = '';
            addServiceRow();
            addMaterialRow();
        }

        function searchAssetByPlate(value) {
            const suggestions = document.getElementById('plateSuggestions');
            const query = value.trim().toUpperCase();

            if (!query) {
                suggestions.style.display = 'none';
                clearServiceAssetFields();
                return;
            }

            const matches = assets.filter(a => a.plateNumber.toUpperCase().includes(query));

            if (matches.length === 0) {
                suggestions.style.display = 'none';
                clearServiceAssetFields();
                return;
            }

            suggestions.style.display = 'block';
            suggestions.innerHTML = matches.map(a => `
                <div onclick="selectServiceAsset('${a.assetNum}')"
                     style="padding: 0.75rem 1rem; cursor: pointer; border-bottom: 1px solid #f0f0f0; display: flex; justify-content: space-between; align-items: center;"
                     onmouseover="this.style.background='#f7fafc'" onmouseout="this.style.background='white'">
                    <span><strong>${a.plateNumber}</strong></span>
                    <span style="color: #718096; font-size: 0.85rem;">${a.assetNum} · ${a.icon} ${a.type.charAt(0).toUpperCase() + a.type.slice(1)}</span>
                </div>
            `).join('');

            if (matches.length === 1 && matches[0].plateNumber.toUpperCase() === query) {
                selectServiceAsset(matches[0].assetNum);
                suggestions.style.display = 'none';
            }
        }

        function selectServiceAsset(assetNum) {
            const asset = assets.find(a => a.assetNum === assetNum);
            if (!asset) return;
            const typeLabels = { car: 'Car', truck: 'Truck' };
            document.getElementById('servicePlateSearch').value = asset.plateNumber;
            document.getElementById('serviceAssetNumDisplay').value = asset.assetNum;
            document.getElementById('serviceAssetNumHidden').value = asset.assetNum;
            document.getElementById('serviceAssetTypeDisplay').value = asset.icon + ' ' + (typeLabels[asset.type] || asset.type);
            document.getElementById('serviceAssetDescription').value = asset.assetDescription || '';
            document.getElementById('plateSuggestions').style.display = 'none';
        }

        function clearServiceAssetFields() {
            document.getElementById('serviceAssetNumDisplay').value = '';
            document.getElementById('serviceAssetNumHidden').value = '';
            document.getElementById('serviceAssetTypeDisplay').value = '';
        }

        function openServiceScanModal() {
            document.getElementById('serviceScanInput').value = '';
            document.getElementById('serviceScanModal').classList.add('active');
        }

        function applyScannedPlate() {
            const val = document.getElementById('serviceScanInput').value.trim().toUpperCase();
            if (!val) return;
            document.getElementById('servicePlateSearch').value = val;
            searchAssetByPlate(val);
            closeModal('serviceScanModal');
        }

        function loadPartDetails() { /* legacy - no-op */ }
        function calculatePartCost() { /* legacy - no-op */ }
        function loadAssetForService() { /* legacy - no-op */ }

        function viewServiceDetails(serviceId) {
            const service = serviceTransactions.find(s => s.serviceId === serviceId);
            if (!service) return;

            const statusStyles = {
                pending:  { bg: '#fefcbf', color: '#744210', label: 'Pending' },
                ongoing:  { bg: '#bee3f8', color: '#2c5282', label: 'Ongoing' },
                complete: { bg: '#c6f6d5', color: '#276749', label: 'Completed' }
            };
            const st = statusStyles[service.status] || statusStyles.pending;

            document.getElementById('sdAssetNum').textContent = service.assetNum;
            document.getElementById('sdAssetDesc').textContent = service.assetDescription || '-';
            document.getElementById('sdDate').textContent = new Date(service.dateServiced).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
            document.getElementById('sdMechanic').textContent = '🔧 ' + (service.mechanicName || '-');
            document.getElementById('sdCreatedBy').textContent = service.createdBy || '-';
            document.getElementById('sdCreatedOn').textContent = new Date(service.createdOn).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
            document.getElementById('sdTotalCost').textContent = '₱' + parseFloat(service.totalCost).toLocaleString('en-PH', { minimumFractionDigits: 2 });

            // Services rendered table
            const rowStyle = 'display:grid;grid-template-columns:2fr 0.5fr 0.5fr 1fr;gap:0.5rem;padding:0.6rem 0;border-bottom:1px solid #f0f4f8;font-size:0.88rem;';
            const headStyle = rowStyle + 'font-weight:700;color:#718096;font-size:0.78rem;text-transform:uppercase;letter-spacing:0.4px;';
            let svcHtml = `<div style="${headStyle}"><div>Description</div><div>Qty</div><div>UOM</div><div style="text-align:right;">Cost</div></div>`;
            if (service.servicesRendered && service.servicesRendered.length > 0) {
                svcHtml += service.servicesRendered.filter(s => s.description).map(s =>
                    `<div style="${rowStyle}"><div>${s.description}</div><div>${s.quantity}</div><div style="color:#718096;">${s.uom || '-'}</div><div style="text-align:right;font-weight:600;color:#2b6cb0;">₱${parseFloat(s.cost).toLocaleString('en-PH',{minimumFractionDigits:2})}</div></div>`
                ).join('');
            } else {
                svcHtml += `<div style="color:#a0aec0;font-size:0.88rem;padding:0.75rem 0;">No services recorded.</div>`;
            }
            document.getElementById('sdServicesTable').innerHTML = svcHtml;

            // Materials table
            let partsHtml = `<div style="${headStyle}"><div>Item</div><div>Qty</div><div>UOM</div><div style="text-align:right;">Cost</div></div>`;
            if (service.spareParts && service.spareParts.length > 0) {
                partsHtml += service.spareParts.filter(p => p.name).map(p =>
                    `<div style="${rowStyle}"><div>${p.name}</div><div>${p.quantity}</div><div style="color:#718096;">${p.uom || '-'}</div><div style="text-align:right;font-weight:600;color:#276749;">₱${parseFloat(p.cost).toLocaleString('en-PH',{minimumFractionDigits:2})}</div></div>`
                ).join('');
            } else {
                partsHtml += `<div style="color:#a0aec0;font-size:0.88rem;padding:0.75rem 0;">No materials used.</div>`;
            }
            document.getElementById('sdPartsTable').innerHTML = partsHtml;

            document.getElementById('serviceDetailsModal').classList.add('active');
        }

        function editService(serviceId) {
            const service = serviceTransactions.find(s => s.serviceId === serviceId);
            if (!service) return;

            openAddServiceModal();
            document.getElementById('serviceModalTitle').textContent = 'Edit Service Transaction';

            const form = document.getElementById('addServiceForm');
            form.dataset.editingServiceId = serviceId;

            // Fill plate/asset fields
            const asset = assets.find(a => a.assetNum === service.assetNum);
            if (asset) {
                selectServiceAsset(asset.assetNum);
            } else {
                document.getElementById('serviceAssetNumHidden').value = service.assetNum;
                document.getElementById('serviceAssetNumDisplay').value = service.assetNum;
            }

            form.elements.dateServiced.value = service.dateServiced;
            document.getElementById('serviceAssetDescription').value = service.assetDescription || '';
            document.getElementById('serviceMechanicName').value = service.mechanicName || '';
            // Populate service rendered rows
            const svcContainer = document.getElementById('serviceRowsContainer');
            if (svcContainer && service.servicesRendered && service.servicesRendered.length > 0) {
                svcContainer.innerHTML = '';
                service.servicesRendered.forEach(s => {
                    addServiceRow(s.description || '', s.quantity || '', s.uom || '', s.cost || '');
                });
            }

            // Populate material rows
            const matContainer = document.getElementById('materialRowsContainer');
            if (matContainer && service.spareParts && service.spareParts.length > 0) {
                matContainer.innerHTML = '';
                service.spareParts.forEach(p => {
                    addMaterialRow(p.itemNum || '', p.quantity || '', p.uom || '', p.cost || '');
                });
            }

            calculateTotalCost();
        }

        function deleteService(serviceId) {
            const service = serviceTransactions.find(s => s.serviceId === serviceId);
            if (!service) return;

            if (confirm(`?��? Are you sure you want to delete this service?\n\nService ID: ${serviceId}\nAsset: ${service.assetNum}\nDate: ${new Date(service.dateServiced).toLocaleDateString()}`)) {
                serviceTransactions = serviceTransactions.filter(s => s.serviceId !== serviceId);
                renderServicesList();
                alert('✅ Service transaction deleted successfully.');
            }
        }

        // Service Form Submission
        document.getElementById('addServiceForm')?.addEventListener('submit', (e) => {
            e.preventDefault();

            const form = e.target;
            const assetNum = document.getElementById('serviceAssetNumHidden').value;

            if (!assetNum) {
                alert('Please search and select an asset by plate number first.');
                return;
            }

            // Validate material quantities against stock
            let stockError = false;
            document.querySelectorAll('#materialRowsContainer .material-row').forEach(row => {
                const opt = row.querySelector('.mat-item').options[row.querySelector('.mat-item').selectedIndex];
                if (!opt || !opt.value) return;
                const stock = parseInt(opt.dataset.stock || 0);
                const qty = parseFloat(row.querySelector('.mat-qty').value) || 0;
                if (qty > stock) {
                    stockError = true;
                    row.querySelector('.mat-qty').style.borderColor = '#e53e3e';
                }
            });
            if (stockError) {
                alert('⚠️ One or more materials exceed available stock. Please fix the quantities before saving.');
                return;
            }

            // Generate Service ID
            const editingServiceId = form.dataset.editingServiceId;
            const existingService = editingServiceId
                ? serviceTransactions.find(s => s.serviceId === editingServiceId)
                : null;
            const serviceId = existingService ? existingService.serviceId : 'SVC-' + String(nextServiceId).padStart(3, '0');

            // Check if editing existing service
            // Collect services rendered from dynamic rows
            const servicesRendered = [];
            document.querySelectorAll('#serviceRowsContainer .service-row').forEach(row => {
                const desc = row.querySelector('.svc-item').value.trim();
                const qty = parseFloat(row.querySelector('.svc-qty').value) || 1;
                const uom = row.querySelector('.svc-uom').value || '';
                const cost = parseFloat(row.querySelector('.svc-cost').value) || 0;
                if (desc) servicesRendered.push({ description: desc, quantity: qty, uom: uom, cost: cost });
            });

            // Collect materials from dynamic rows
            const spareParts = [];
            document.querySelectorAll('#materialRowsContainer .material-row').forEach(row => {
                const itemNum = row.querySelector('.mat-item').value;
                const qty = parseFloat(row.querySelector('.mat-qty').value) || 0;
                const uom = row.querySelector('.mat-uom').value || '';
                const cost = parseFloat(row.querySelector('.mat-cost').value) || 0;
                if (itemNum && qty > 0) {
                    const inventoryItem = inventory.find(i => i.itemNum === itemNum);
                    spareParts.push({ itemNum: itemNum, name: inventoryItem ? inventoryItem.itemName : itemNum, quantity: qty, uom: uom, cost: cost });
                }
            });
            
            // Calculate total cost
            const totalCost = calculateTotalCost();
            
            const serviceData = {
                serviceId: serviceId,
                dateServiced: form.elements.dateServiced.value,
                assetNum: assetNum,
                assetDescription: document.getElementById('serviceAssetDescription').value,
                mechanicName: form.elements.mechanicName.value.trim(),
                servicesRendered: servicesRendered,
                spareParts: spareParts,
                status: 'pending',
                totalCost: totalCost,
                createdBy: currentUser ? currentUser.name : 'Unknown',
                createdOn: existingService ? existingService.createdOn : new Date().toISOString()
            };

            // Check if service is being marked as complete
            const wasComplete = existingService && existingService.status === 'complete';

            if (existingService) {
                // Preserve status when editing (don't reset to pending if already ongoing/complete)
                serviceData.status = existingService.status;
                Object.assign(existingService, serviceData);
                alert(`✅ Service ${serviceId} updated successfully!`);
            } else {
                // Add new service as pending, set asset to maintenance
                serviceTransactions.push(serviceData);
                nextServiceId++;
                const asset = assets.find(a => a.assetNum === assetNum);
                if (asset) asset.status = 'maintenance';
                alert(`✅ Service ${serviceId} created successfully!`);
            }

            renderServicesList();
            renderAssetsList();
            if (typeof renderStaffServicesList === 'function') renderStaffServicesList();
            if (typeof renderStaffAssetsList === 'function') renderStaffAssetsList();
            closeModal('addServiceModal');
            form.reset();
            delete form.dataset.editingServiceId;
            document.getElementById('servicePlateSearch').value = '';
            document.getElementById('serviceAssetNumDisplay').value = '';
            document.getElementById('serviceAssetNumHidden').value = '';
            document.getElementById('serviceAssetTypeDisplay').value = '';
            document.getElementById('plateSuggestions').style.display = 'none';
            document.getElementById('totalCostDisplay').textContent = '₱0.00';
        });

        // Function to create issuances from completed service
        function createIssuancesFromService(service) {
            const dateServiced = service.dateServiced;
            const assetNum = service.assetNum;
            const assetDescription = service.assetDescription;
            
            // Create issuance for services rendered
            if (service.servicesRendered && service.servicesRendered.length > 0) {
                service.servicesRendered.forEach(svc => {
                    if (svc.description) {
                        const issuanceData = {
                            id: nextIssuanceId++,
                            date: dateServiced,
                            assetNum: assetNum,
                            assetDescription: assetDescription,
                            itemNum: 'SVC-' + nextIssuanceId,
                            description: svc.description,
                            itemType: 'Service',
                            commodityGroup: 'Auto Service',
                            uom: svc.uom || 'Service',
                            quantity: 1,
                            unitCost: svc.cost,
                            subtotal: svc.cost,
                            createdBy: currentUser ? currentUser.name : 'Unknown',
                            createdOn: new Date().toISOString()
                        };
                        issuances.push(issuanceData);
                    }
                });
            }
            
            // Create issuance for spare parts and deduct from inventory
            if (service.spareParts && service.spareParts.length > 0) {
                service.spareParts.forEach(part => {
                    if (part.name) {
                        // Find matching inventory item by itemNum (preferred) or name
                        const inventoryItem = inventory.find(item => 
                            item.itemNum === part.itemNum ||
                            item.itemName.toLowerCase() === part.name.toLowerCase()
                        );
                        
                        let itemNum = part.itemNum || 'PART-' + nextIssuanceId;
                        let commodityGroup = 'Spare Parts';
                        let uom = 'pcs';
                        
                        if (inventoryItem) {
                            itemNum = inventoryItem.itemNum;
                            commodityGroup = inventoryItem.commodityGroup;
                            uom = inventoryItem.unit;
                            
                            // Deduct from inventory
                            inventoryItem.stock -= part.quantity;
                            
                            // Update inventory status
                            if (inventoryItem.stock <= 0) {
                                inventoryItem.status = 'out_of_stock';
                            } else if (inventoryItem.stock <= inventoryItem.reorderLevel) {
                                inventoryItem.status = 'low_stock';
                            } else {
                                inventoryItem.status = 'in_stock';
                            }
                            
                            // Refresh inventory display if on that section
                            if (typeof renderInventoryList === 'function') {
                                renderInventoryList();
                            }
                        }
                        
                        const issuanceData = {
                            id: nextIssuanceId++,
                            date: dateServiced,
                            assetNum: assetNum,
                            assetDescription: assetDescription,
                            itemNum: itemNum,
                            description: part.name,
                            itemType: 'Material',
                            commodityGroup: commodityGroup,
                            uom: uom,
                            quantity: part.quantity,
                            unitCost: part.cost / part.quantity,
                            subtotal: part.cost,
                            createdBy: currentUser ? currentUser.name : 'Unknown',
                            createdOn: new Date().toISOString()
                        };
                        issuances.push(issuanceData);
                    }
                });
            }
            
            // Refresh issuances display if on that section
            if (typeof renderIssuancesList === 'function') {
                renderIssuancesList();
            }
        }

        // Service search functionality
        document.getElementById('serviceSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#servicesList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        // Issuance Functions
        function renderIssuancesList() {
            const list = document.getElementById('issuancesList');
            if (!list) return;

            if (issuances.length === 0) {
                list.innerHTML = '<div class="table-row" style="text-align: center; color: #718096; padding: 2rem;">No issuances recorded yet. Click "New Issuance" to create one.</div>';
                updateIssuanceStats();
                return;
            }

            list.innerHTML = issuances.map(issuance => `
                <div class="table-row" style="grid-template-columns: 100px 120px 120px 200px 100px 140px 80px 90px 110px 110px 130px;">
                    <div>${new Date(issuance.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}</div>
                    <div><strong>${issuance.assetNum}</strong></div>
                    <div><strong>${issuance.itemNum}</strong></div>
                    <div style="font-size: 0.85rem; color: #4a5568;">${issuance.description}</div>
                    <div>${issuance.itemType}</div>
                    <div>${issuance.commodityGroup}</div>
                    <div>${issuance.uom}</div>
                    <div><strong>${issuance.quantity}</strong></div>
                    <div>₱${parseFloat(issuance.unitCost).toLocaleString('en-PH', {minimumFractionDigits: 2})}</div>
                    <div><strong>₱${parseFloat(issuance.subtotal).toLocaleString('en-PH', {minimumFractionDigits: 2})}</strong></div>
                    <div>
                        <button class="btn-small btn-primary" onclick="viewIssuanceDetails(${issuance.id})" title="View">👁️</button>
                        <button class="btn-small btn-secondary" onclick="editIssuance(${issuance.id})" title="Edit">✏️</button>
                    </div>
                </div>
            `).join('');

            updateIssuanceStats();
        }

        function updateIssuanceStats() {
            document.getElementById('totalIssuances').textContent = issuances.length;
            document.getElementById('totalServices').textContent = issuances.filter(i => i.itemType === 'Service').length;
            document.getElementById('totalMaterials').textContent = issuances.filter(i => i.itemType === 'Material').length;
        }

        function openAddIssuanceModal() {
            document.getElementById('addIssuanceModal').classList.add('active');
            document.getElementById('issuanceModalTitle').textContent = 'New Issuance';
            
            // Set default date to today
            const dateInput = document.querySelector('[name="issuanceDate"]');
            dateInput.value = new Date().toISOString().split('T')[0];
            
            // Populate asset dropdown
            const assetSelect = document.getElementById('issuanceAssetSelect');
            assetSelect.innerHTML = '<option value="">Select Asset</option>' + 
                assets.map(asset => `<option value="${asset.assetNum}">${asset.assetNum} - ${asset.assetDescription}</option>`).join('');
            
            // Populate item dropdown from inventory
            const itemSelect = document.getElementById('issuanceItemSelect');
            itemSelect.innerHTML = '<option value="">Select Item</option>' + 
                inventory.map(item => `<option value="${item.itemNum}">${item.itemNum} - ${item.itemName}</option>`).join('');
            
            // Reset form
            document.getElementById('addIssuanceForm').reset();
            dateInput.value = new Date().toISOString().split('T')[0];
            document.getElementById('issuanceAssetDescription').value = '';
            document.getElementById('issuanceDescription').value = '';
            document.getElementById('issuanceCommodityGroup').value = '';
            document.getElementById('issuanceUOM').value = '';
            document.getElementById('issuanceUnitCost').value = '';
            document.getElementById('subtotalDisplay').textContent = '₱0.00';
        }

        function loadAssetDescription() {
            const assetNum = document.getElementById('issuanceAssetSelect').value;
            const descInput = document.getElementById('issuanceAssetDescription');
            
            if (!assetNum) {
                descInput.value = '';
                return;
            }

            const asset = assets.find(a => a.assetNum === assetNum);
            if (asset) {
                descInput.value = asset.assetDescription;
            }
        }

        function loadItemDetails() {
            const itemNum = document.getElementById('issuanceItemSelect').value;
            
            if (!itemNum) {
                document.getElementById('issuanceDescription').value = '';
                document.getElementById('issuanceCommodityGroup').value = '';
                document.getElementById('issuanceUOM').value = '';
                document.getElementById('issuanceUnitCost').value = '';
                return;
            }

            const item = inventory.find(i => i.itemNum === itemNum);
            if (item) {
                document.getElementById('issuanceDescription').value = item.longDescription || item.itemName;
                document.getElementById('issuanceCommodityGroup').value = item.commodityGroup;
                document.getElementById('issuanceUOM').value = item.unit;
                document.getElementById('issuanceUnitCost').value = item.price;
            }
        }

        function calculateSubtotal() {
            const quantity = parseFloat(document.querySelector('[name="quantity"]')?.value) || 0;
            const unitCost = parseFloat(document.getElementById('issuanceUnitCost').value) || 0;
            const subtotal = quantity * unitCost;
            
            document.getElementById('subtotalDisplay').textContent = '₱' + subtotal.toLocaleString('en-PH', {minimumFractionDigits: 2});
            return subtotal;
        }

        function viewIssuanceDetails(id) {
            const issuance = issuances.find(i => i.id === id);
            if (!issuance) return;

            const typeColors = {
                Service:  { bg: '#ebf8ff', color: '#2c5282' },
                Material: { bg: '#f0fff4', color: '#276749' }
            };
            const tc = typeColors[issuance.itemType] || { bg: '#f7fafc', color: '#4a5568' };

            document.getElementById('idAssetNum').textContent = issuance.assetNum;
            document.getElementById('idAssetDesc').textContent = issuance.assetDescription || '-';
            document.getElementById('idItemTypeBadge').innerHTML =
                `<span style="background:${tc.bg};color:${tc.color};padding:0.3rem 0.85rem;border-radius:20px;font-size:0.78rem;font-weight:700;">${issuance.itemType || '-'}</span>`;

            const fmt = (d) => new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
            const money = (v) => '₱' + parseFloat(v).toLocaleString('en-PH', { minimumFractionDigits: 2 });

            document.getElementById('idDate').textContent = fmt(issuance.date);
            document.getElementById('idSubtotal').textContent = money(issuance.subtotal);
            document.getElementById('idSubtotal2').textContent = money(issuance.subtotal);
            document.getElementById('idQty').textContent = issuance.quantity;
            document.getElementById('idUOM').textContent = issuance.uom || '-';
            document.getElementById('idUnitCost').textContent = money(issuance.unitCost);

            const gridItems = [
                { label: 'Item Number',      value: issuance.itemNum },
                { label: 'Description',      value: issuance.description || '-' },
                { label: 'Commodity Group',  value: issuance.commodityGroup || '-' },
                { label: 'Created By',       value: issuance.createdBy || '-' },
                { label: 'Created On',       value: issuance.createdOn ? fmt(issuance.createdOn) : '-' },
            ];
            document.getElementById('idItemGrid').innerHTML = gridItems.map(item => `
                <div style="background: #f7fafc; border-radius: 10px; padding: 0.85rem 1rem;">
                    <div style="font-size: 0.7rem; color: #718096; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; margin-bottom: 0.3rem;">${item.label}</div>
                    <div style="font-weight: 700; color: #1a202c; font-size: 0.9rem;">${item.value}</div>
                </div>
            `).join('');

            document.getElementById('issuanceDetailsModal').classList.add('active');
        }

        function editIssuance(id) {
            const issuance = issuances.find(i => i.id === id);
            if (!issuance) return;

            // Open modal in edit mode
            document.getElementById('addIssuanceModal').classList.add('active');
            document.getElementById('issuanceModalTitle').textContent = 'Edit Issuance';
            
            // Populate form
            const form = document.getElementById('addIssuanceForm');
            
            // Set date
            form.elements.issuanceDate.value = issuance.date;
            
            // Populate asset dropdown
            const assetSelect = document.getElementById('issuanceAssetSelect');
            assetSelect.innerHTML = '<option value="">Select Asset</option>' + 
                assets.map(asset => `<option value="${asset.assetNum}">${asset.assetNum} - ${asset.assetDescription}</option>`).join('');
            assetSelect.value = issuance.assetNum;
            document.getElementById('issuanceAssetDescription').value = issuance.assetDescription;
            
            // Populate item dropdown
            const itemSelect = document.getElementById('issuanceItemSelect');
            itemSelect.innerHTML = '<option value="">Select Item</option>' + 
                inventory.map(item => `<option value="${item.itemNum}">${item.itemNum} - ${item.itemName}</option>`).join('');
            itemSelect.value = issuance.itemNum;
            
            // Load item details
            document.getElementById('issuanceDescription').value = issuance.description;
            document.getElementById('issuanceCommodityGroup').value = issuance.commodityGroup;
            document.getElementById('issuanceUOM').value = issuance.uom;
            document.getElementById('issuanceUnitCost').value = issuance.unitCost;
            
            form.elements.itemType.value = issuance.itemType;
            form.elements.quantity.value = issuance.quantity;
            
            // Store the ID for updating
            form.dataset.editingId = id;
            
            // Calculate subtotal
            calculateSubtotal();
        }

        function deleteIssuance(id) {
            const issuance = issuances.find(i => i.id === id);
            if (!issuance) return;

            if (confirm(`⚠️ Are you sure you want to delete this issuance?\n\nItem: ${issuance.itemNum}\nDescription: ${issuance.description}`)) {
                issuances = issuances.filter(i => i.id !== id);
                renderIssuancesList();
                alert('✅ Issuance deleted successfully.');
            }
        }

        // Issuance Form Submission
        document.getElementById('addIssuanceForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            
            const form = e.target;
            const editingId = form.dataset.editingId ? parseInt(form.dataset.editingId) : null;
            
            // Check if editing existing issuance
            const existingIssuance = editingId ? issuances.find(i => i.id === editingId) : null;
            
            const subtotal = calculateSubtotal();
            
            const issuanceData = {
                id: existingIssuance ? existingIssuance.id : nextIssuanceId++,
                date: form.elements.issuanceDate.value,
                assetNum: form.elements.assetNum.value,
                assetDescription: document.getElementById('issuanceAssetDescription').value,
                itemNum: form.elements.itemNum.value,
                description: document.getElementById('issuanceDescription').value,
                itemType: form.elements.itemType.value,
                commodityGroup: document.getElementById('issuanceCommodityGroup').value,
                uom: document.getElementById('issuanceUOM').value,
                quantity: parseInt(form.elements.quantity.value),
                unitCost: parseFloat(document.getElementById('issuanceUnitCost').value),
                subtotal: subtotal,
                createdBy: currentUser ? currentUser.name : 'Unknown',
                createdOn: existingIssuance ? existingIssuance.createdOn : new Date().toISOString()
            };

            if (existingIssuance) {
                // Update existing issuance
                Object.assign(existingIssuance, issuanceData);
                alert(`✅ Issuance updated successfully!`);
            } else {
                // Add new issuance
                issuances.push(issuanceData);
                alert(`✅ Issuance created successfully!`);
            }

            renderIssuancesList();
            closeModal('addIssuanceModal');
            form.reset();
            delete form.dataset.editingId;
            document.getElementById('subtotalDisplay').textContent = '₱0.00';
        });

        // Issuance search functionality
        document.getElementById('issuanceSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#issuancesList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        // Inventory Management Functions
        let currentEditingInventoryItem = null;
        let currentPhysicalCountItem = null;

        function renderInventoryList() {
            const inventoryList = document.getElementById('inventoryList');
            if (!inventoryList) return;

            const search = (document.getElementById('inventorySearch')?.value || '').toLowerCase();

            const statusBadges = {
                low_stock:    '<span class="status-badge status-overdue">Low Stock</span>',
                in_stock:     '<span class="status-badge status-active">In Stock</span>',
                out_of_stock: '<span class="status-badge status-pending">Out of Stock</span>'
            };

            const cols = '100px 1.5fr 1fr 100px 90px 90px 110px 110px';

            const filtered = inventory.filter(item =>
                item.itemNum.toLowerCase().includes(search) ||
                item.itemName.toLowerCase().includes(search) ||
                (item.commodityGroup || '').toLowerCase().includes(search)
            );

            if (filtered.length === 0) {
                inventoryList.innerHTML = '<div style="padding:2rem;text-align:center;color:#718096;">No items found.</div>';
                updateInventoryStats();
                return;
            }

            inventoryList.innerHTML = filtered.map(item => `
                <div class="table-row" style="grid-template-columns:${cols};">
                    <div><strong>${item.itemNum}</strong></div>
                    <div>${item.itemName}</div>
                    <div>${item.commodityGroup}</div>
                    <div style="text-align:center;">${item.stock} <span style="font-size:0.75rem;color:#718096;">${item.unit}</span></div>
                    <div style="text-align:center;">${item.minLevel ?? item.reorderLevel ?? '-'}</div>
                    <div style="text-align:center;">${item.maxLevel ?? '-'}</div>
                    <div>${statusBadges[item.status] || '-'}</div>
                    <div style="display:flex;gap:0.3rem;">
                        <button class="btn-small btn-primary" onclick="viewItemDetails('${item.itemNum}')" title="View">👁️</button>
                        <button class="btn-small btn-secondary" onclick="editInventoryItem('${item.itemNum}')" title="Edit">✏️</button>
                        <button class="btn-small btn-danger" onclick="deleteInventoryItem('${item.itemNum}')" title="Delete">🗑️</button>
                    </div>
                </div>
            `).join('');

            updateInventoryStats();
        }

        function updateInventoryStats() {
            const totalItems = inventory.length;
            const lowStockItems = inventory.filter(i => i.status === 'low_stock').length;
            const totalValue = inventory.reduce((sum, item) => sum + (item.stock * item.price), 0);

            document.getElementById('totalInventoryItems').textContent = totalItems;
            document.getElementById('lowStockCount').textContent = lowStockItems;
            document.getElementById('totalInventoryValue').textContent = `₱${totalValue.toLocaleString('en-PH')}`;
        }

        function openAddInventoryModal() {
            currentEditingInventoryItem = null;
            document.getElementById('inventoryModalTitle').textContent = 'Add New Inventory Item';
            document.getElementById('addInventoryForm').reset();
            document.getElementById('invScanInput').value = '';
            document.getElementById('invScanFeedback').textContent = '';
            document.getElementById('invItemPreview').style.display = 'none';
            ['invItemNum','invItemName','invDescription','invCommodityGroup',
             'invUnit','invPrice','invBarcode','invQrcode'].forEach(id => {
                const el = document.getElementById(id);
                if (el) el.value = '';
            });
            document.getElementById('addInventoryModal').classList.add('active');
        }

        function autofillInventoryFromScan(value) {
            const query = value.trim().toLowerCase();
            const feedback = document.getElementById('invScanFeedback');
            const preview  = document.getElementById('invItemPreview');
            if (!query) {
                feedback.textContent = '';
                preview.style.display = 'none';
                return;
            }

            const found = itemMaster.find(i =>
                (i.barcode && i.barcode.toLowerCase() === query) ||
                (i.qrcode  && i.qrcode.toLowerCase()  === query)
            ) || itemMaster.find(i =>
                (i.itemNum && i.itemNum.toLowerCase().includes(query)) ||
                (i.itemName && i.itemName.toLowerCase().includes(query))
            );

            if (found) {
                // Populate hidden fields
                document.getElementById('invItemNum').value        = found.itemNum        || '';
                document.getElementById('invItemName').value       = found.itemName       || '';
                document.getElementById('invDescription').value    = found.description    || '';
                document.getElementById('invCommodityGroup').value = found.commodityGroup || '';
                document.getElementById('invUnit').value           = found.uom            || '';
                document.getElementById('invPrice').value          = found.cost           || '';
                document.getElementById('invBarcode').value        = found.barcode        || '';
                document.getElementById('invQrcode').value         = found.qrcode         || '';

                // Show preview card
                document.getElementById('invPreviewNum').textContent      = found.itemNum || '-';
                document.getElementById('invPreviewName').textContent     = found.itemName || '-';
                document.getElementById('invPreviewGroup').textContent    = found.commodityGroup || '-';
                document.getElementById('invPreviewUnitCost').textContent = (found.uom || '-') + '  ·  ₱' + (found.cost || 0).toLocaleString('en-PH', { minimumFractionDigits: 2 });
                document.getElementById('invPreviewDesc').textContent     = found.description || 'No description.';
                preview.style.display = 'block';

                feedback.style.color = '#38a169';
                feedback.textContent = '';
            } else {
                preview.style.display = 'none';
                feedback.style.color = '#e53e3e';
                feedback.textContent = '❌ No item found in Item Master.';
            }
        }

        function openInvScanModal() {
            document.getElementById('invScanModalInput').value = '';
            document.getElementById('invScanModal').classList.add('active');
        }

        function applyInvScanModal() {
            const val = document.getElementById('invScanModalInput').value.trim();
            if (!val) { alert('Please enter a barcode or QR code.'); return; }
            closeModal('invScanModal');
            document.getElementById('invScanInput').value = val;
            autofillInventoryFromScan(val);
        }

        function editInventoryItem(itemNum) {
            const item = inventory.find(i => i.itemNum === itemNum);
            if (!item) return;

            currentEditingInventoryItem = item;
            document.getElementById('inventoryModalTitle').textContent = 'Edit Inventory Item';
            document.getElementById('invScanInput').value = '';
            document.getElementById('invScanFeedback').textContent = '';

            const form = document.getElementById('addInventoryForm');
            document.getElementById('invItemNum').value        = item.itemNum        || '';
            document.getElementById('invItemName').value       = item.itemName       || '';
            document.getElementById('invDescription').value    = item.longDescription|| '';
            document.getElementById('invCommodityGroup').value = item.commodityGroup || '';
            document.getElementById('invUnit').value           = item.unit           || '';
            document.getElementById('invPrice').value          = item.price          || '';
            document.getElementById('invBarcode').value        = item.barcode        || '';
            document.getElementById('invQrcode').value         = item.qrcode         || '';
            form.elements.stock.value      = item.stock        || 0;
            form.elements.minLevel.value   = item.minLevel     || item.reorderLevel || 0;
            form.elements.maxLevel.value   = item.maxLevel     || 0;
            form.elements.reorderQty.value = item.reorderQty   || 0;

            // Show preview card
            document.getElementById('invPreviewNum').textContent      = item.itemNum || '-';
            document.getElementById('invPreviewName').textContent     = item.itemName || '-';
            document.getElementById('invPreviewGroup').textContent    = item.commodityGroup || '-';
            document.getElementById('invPreviewUnitCost').textContent = (item.unit || '-') + '  ·  ₱' + (item.price || 0).toLocaleString('en-PH', { minimumFractionDigits: 2 });
            document.getElementById('invPreviewDesc').textContent     = item.longDescription || 'No description.';
            document.getElementById('invItemPreview').style.display   = 'block';

            document.getElementById('addInventoryModal').classList.add('active');
        }

        function deleteInventoryItem(itemNum) {
            const item = inventory.find(i => i.itemNum === itemNum);
            if (!item) return;

            if (confirm(`⚠️ Are you sure you want to delete ${item.itemName}?\n\nThis action cannot be undone.`)) {
                inventory = inventory.filter(i => i.itemNum !== itemNum);
                renderInventoryList();
                alert(`✅ Item ${item.itemName} has been deleted successfully.`);
            }
        }

        function viewItemDetails(itemNum) {
            const item = inventory.find(i => i.itemNum === itemNum);
            if (!item) return;

            const statusMap = {
                in_stock:     { bg: '#c6f6d5', color: '#276749', label: 'In Stock' },
                low_stock:    { bg: '#fefcbf', color: '#744210', label: 'Low Stock' },
                out_of_stock: { bg: '#fed7d7', color: '#742a2a', label: 'Out of Stock' }
            };
            const st = statusMap[item.status] || statusMap.in_stock;

            // Header
            document.getElementById('viItemName').textContent = item.itemName;
            document.getElementById('viItemNum').textContent = item.itemNum + (item.itemId ? '  ·  ' + item.itemId : '');
            document.getElementById('viStatusBadge').innerHTML =
                `<span style="background:${st.bg};color:${st.color};padding:0.3rem 0.85rem;border-radius:20px;font-size:0.78rem;font-weight:700;">${st.label}</span>`;
            document.getElementById('viGroupBadge').textContent = item.commodityGroup || '-';

            // Stats
            document.getElementById('viStock').innerHTML = `${item.stock} <span style="font-size:0.85rem;font-weight:600;color:#718096;">${item.unit}</span>`;
            document.getElementById('viPrice').textContent = '₱' + item.price.toLocaleString('en-PH', { minimumFractionDigits: 2 });
            document.getElementById('viReorder').innerHTML = `${item.reorderLevel} <span style="font-size:0.85rem;font-weight:600;color:#718096;">${item.unit}</span>`;

            // Description
            document.getElementById('viDesc').textContent = item.longDescription || 'No description available.';

            // Info grid
            const totalValue = item.stock * item.price;
            const lastCount = item.lastPhysicalCount
                ? new Date(item.lastPhysicalCount).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                : 'N/A';
            const infoItems = [
                { label: 'Item ID',            value: item.itemId || '-' },
                { label: 'Commodity Group',    value: item.commodityGroup || '-' },
                { label: 'Unit of Measure',    value: item.unit || '-' },
                { label: 'Total Stock Value',  value: '₱' + totalValue.toLocaleString('en-PH', { minimumFractionDigits: 2 }) },
                { label: 'Last Physical Count', value: lastCount },
                { label: 'Status',             value: st.label },
            ];
            document.getElementById('viInfoGrid').innerHTML = infoItems.map(i => `
                <div style="background:#f7fafc;border-radius:10px;padding:0.85rem 1rem;">
                    <div style="font-size:0.7rem;color:#718096;font-weight:700;text-transform:uppercase;letter-spacing:0.4px;margin-bottom:0.3rem;">${i.label}</div>
                    <div style="font-weight:700;color:#1a202c;font-size:0.92rem;">${i.value}</div>
                </div>
            `).join('');

            // Barcode / QR
            document.getElementById('viBarcode').textContent = item.barcode || '-';
            document.getElementById('viQR').textContent = item.qrcode || '-';

            document.getElementById('viewItemModal').classList.add('active');
        }

        function generateBarcode() {
            const timestamp = Date.now().toString().slice(-13);
            document.querySelector('[name="barcode"]').value = timestamp;
            alert('✅ Barcode generated: ' + timestamp);
        }

        function generateQRCode() {
            const itemNum = document.querySelector('[name="itemNum"]').value;
            if (!itemNum) {
                alert('⚠️ Please enter Item Number first');
                return;
            }
            const qrCode = 'QR-' + itemNum;
            document.querySelector('[name="qrcode"]').value = qrCode;
            alert('??QR Code generated: ' + qrCode);
        }

        function openScanBarcodeModal() {
            document.getElementById('scanBarcodeModal').classList.add('active');
            document.getElementById('manualBarcodeInput').value = '';
        }

        function openScanQRModal() {
            document.getElementById('scanQRModal').classList.add('active');
            document.getElementById('manualQRInput').value = '';
        }

        function searchByBarcode() {
            const barcode = document.getElementById('manualBarcodeInput').value.trim();
            if (!barcode) {
                alert('?��? Please enter a barcode');
                return;
            }

            const item = inventory.find(i => i.barcode === barcode);
            if (item) {
                closeModal('scanBarcodeModal');
                viewItemDetails(item.itemNum);
            } else {
                alert('??No item found with barcode: ' + barcode);
            }
        }

        function searchByQRCode() {
            const qrcode = document.getElementById('manualQRInput').value.trim();
            if (!qrcode) {
                alert('?��? Please enter a QR code');
                return;
            }

            const item = inventory.find(i => i.qrcode === qrcode);
            if (item) {
                closeModal('scanQRModal');
                viewItemDetails(item.itemNum);
            } else {
                alert('??No item found with QR code: ' + qrcode);
            }
        }

        function openPhysicalCountModal() {
            document.getElementById('physicalCountModal').classList.add('active');
            document.getElementById('physicalCountItemInfo').style.display = 'none';
            document.getElementById('physicalCountVariance').style.display = 'none';
            document.getElementById('physicalCountSearch').value = '';
            document.getElementById('physicalCountValue').value = '';
            currentPhysicalCountItem = null;
        }

        function openScanForPhysicalCount() {
            document.getElementById('scanPhysicalCountModal').classList.add('active');
            document.getElementById('scanPhysicalCountInput').value = '';
        }

        function searchScannedItem() {
            const code = document.getElementById('scanPhysicalCountInput').value.trim();
            if (!code) {
                alert('?��? Please enter a barcode or QR code');
                return;
            }

            const item = inventory.find(i => 
                i.barcode === code || i.qrcode === code
            );

            if (item) {
                // Close scan modal
                closeModal('scanPhysicalCountModal');
                
                // Set the item in physical count
                currentPhysicalCountItem = item;
                document.getElementById('physicalCountSearch').value = item.itemNum;
                document.getElementById('physicalCountItemInfo').style.display = 'block';
                document.getElementById('pcItemName').textContent = item.itemName;
                document.getElementById('pcItemCode').textContent = item.itemNum;
                document.getElementById('pcCurrentStock').textContent = `${item.stock} ${item.unit}`;
                document.getElementById('pcUnit').textContent = item.unit;
                
                alert(`??Item found: ${item.itemName}`);
            } else {
                alert('??No item found with this barcode or QR code');
            }
        }

        // Physical count search
        document.getElementById('physicalCountSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.trim().toLowerCase();
            if (searchTerm.length < 3) {
                document.getElementById('physicalCountItemInfo').style.display = 'none';
                currentPhysicalCountItem = null;
                return;
            }

            const item = inventory.find(i => 
                i.barcode.toLowerCase().includes(searchTerm) ||
                i.qrcode.toLowerCase().includes(searchTerm) ||
                i.itemNum.toLowerCase().includes(searchTerm) ||
                i.itemName.toLowerCase().includes(searchTerm)
            );

            if (item) {
                currentPhysicalCountItem = item;
                document.getElementById('physicalCountItemInfo').style.display = 'block';
                document.getElementById('pcItemName').textContent = item.itemName;
                document.getElementById('pcItemCode').textContent = item.itemNum;
                document.getElementById('pcCurrentStock').textContent = `${item.stock} ${item.unit}`;
                document.getElementById('pcUnit').textContent = item.unit;
            } else {
                document.getElementById('physicalCountItemInfo').style.display = 'none';
                currentPhysicalCountItem = null;
            }
        });

        // Physical count value change
        document.getElementById('physicalCountValue')?.addEventListener('input', (e) => {
            if (!currentPhysicalCountItem) return;

            const physicalCount = parseInt(e.target.value);
            const systemBalance = currentPhysicalCountItem.stock;
            const variance = physicalCount - systemBalance;

            if (!isNaN(physicalCount)) {
                const varianceDiv = document.getElementById('physicalCountVariance');
                varianceDiv.style.display = 'block';

                if (variance > 0) {
                    varianceDiv.style.background = '#f0fff4';
                    varianceDiv.style.borderLeft = '4px solid #38a169';
                    document.getElementById('varianceAmount').innerHTML = `
                        <span style="color: #38a169;">+${variance} ${currentPhysicalCountItem.unit}</span>
                        <span style="font-size: 0.9rem; color: #2d3748;"> (Overage)</span>
                    `;
                } else if (variance < 0) {
                    varianceDiv.style.background = '#fed7d7';
                    varianceDiv.style.borderLeft = '4px solid #e53e3e';
                    document.getElementById('varianceAmount').innerHTML = `
                        <span style="color: #e53e3e;">${variance} ${currentPhysicalCountItem.unit}</span>
                        <span style="font-size: 0.9rem; color: #2d3748;"> (Shortage)</span>
                    `;
                } else {
                    varianceDiv.style.background = '#ebf8ff';
                    varianceDiv.style.borderLeft = '4px solid #3182ce';
                    document.getElementById('varianceAmount').innerHTML = `
                        <span style="color: #3182ce;">No Variance</span>
                        <span style="font-size: 0.9rem; color: #2d3748;"> (Balanced)</span>
                    `;
                }
            }
        });

        function submitPhysicalCount() {
            if (!currentPhysicalCountItem) {
                alert('?��? Please select an item first');
                return;
            }

            const physicalCount = parseInt(document.getElementById('physicalCountValue').value);
            if (isNaN(physicalCount) || physicalCount < 0) {
                alert('?��? Please enter a valid physical count');
                return;
            }

            const variance = physicalCount - currentPhysicalCountItem.stock;

            // Update inventory
            const item = inventory.find(i => i.itemNum === currentPhysicalCountItem.itemNum);
            if (item) {
                const oldStock = item.stock;
                item.stock = physicalCount;
                item.lastPhysicalCount = new Date().toISOString().split('T')[0];
                
                // Update status
                if (item.stock === 0) {
                    item.status = 'out_of_stock';
                } else if (item.stock <= item.reorderLevel) {
                    item.status = 'low_stock';
                } else {
                    item.status = 'in_stock';
                }

                // Record physical count
                physicalCountRecords.push({
                    date: new Date().toISOString(),
                    itemNum: item.itemNum,
                    itemName: item.itemName,
                    systemBalance: oldStock,
                    physicalCount: physicalCount,
                    variance: variance,
                    countedBy: currentUser ? currentUser.name : 'Unknown'
                });

                renderInventoryList();
                closeModal('physicalCountModal');

                alert(`??Physical Count Updated!\n\n` +
                      `Item: ${item.itemName}\n` +
                      `Previous Balance: ${oldStock} ${item.unit}\n` +
                      `Physical Count: ${physicalCount} ${item.unit}\n` +
                      `Variance: ${variance > 0 ? '+' : ''}${variance} ${item.unit}\n\n` +
                      `Inventory has been updated.`);
            }
        }

        function exportInventory() {
            alert('?? Export Inventory Report\n\nIn a real implementation, this would generate an Excel or PDF report.');
        }

        function renderInventoryTransactions(filter = '') {
            // Build unified transaction list from deliveries + issuances
            const txns = [];

            // Stock IN — deliveries
            deliveryRecords.forEach(d => {
                txns.push({
                    date: d.date,
                    itemNum: d.itemNum,
                    itemName: d.itemName,
                    description: `Delivery received`,
                    direction: 'in',
                    qty: d.quantityReceived,
                    reference: d.reference || '-',
                    by: d.receivedBy || '-'
                });
            });

            // Stock OUT — issuances
            issuances.forEach(i => {
                txns.push({
                    date: i.date,
                    itemNum: i.itemNum,
                    itemName: i.description || i.itemNum,
                    description: `Issued to ${i.assetNum} — ${i.assetDescription || ''}`,
                    direction: 'out',
                    qty: i.quantity,
                    reference: i.assetNum || '-',
                    by: i.createdBy || '-'
                });
            });

            // Sort newest first
            txns.sort((a, b) => new Date(b.date) - new Date(a.date));

            // Stats
            const filtered = filter
                ? txns.filter(t =>
                    t.itemNum.toLowerCase().includes(filter) ||
                    t.itemName.toLowerCase().includes(filter) ||
                    t.reference.toLowerCase().includes(filter) ||
                    t.by.toLowerCase().includes(filter))
                : txns;

            document.getElementById('txnTotal').textContent = txns.length;
            document.getElementById('txnIn').textContent = txns.filter(t => t.direction === 'in').length;
            document.getElementById('txnOut').textContent = txns.filter(t => t.direction === 'out').length;
            document.getElementById('txnItems').textContent = new Set(txns.map(t => t.itemNum)).size;

            const list = document.getElementById('txnList');
            if (!list) return;

            if (filtered.length === 0) {
                list.innerHTML = '<div class="table-row" style="text-align:center;color:#718096;padding:2rem;">No transactions found.</div>';
                return;
            }

            list.innerHTML = filtered.map(t => {
                const dirBadge = t.direction === 'in'
                    ? '<span style="background:#c6f6d5;color:#276749;padding:0.25rem 0.75rem;border-radius:20px;font-size:0.78rem;font-weight:700;letter-spacing:0.3px;">Receive</span>'
                    : '<span style="background:#fed7d7;color:#c53030;padding:0.25rem 0.75rem;border-radius:20px;font-size:0.78rem;font-weight:700;letter-spacing:0.3px;">Issue</span>';
                const qtyColor = t.direction === 'in' ? '#276749' : '#c53030';
                const qtySign = t.direction === 'in' ? '+' : '-';
                const dateStr = new Date(t.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });

                return `
                    <div class="table-row" style="grid-template-columns: 120px 1fr 1.5fr 80px 80px 100px;">
                        <div style="font-size:0.85rem;color:#4a5568;">${dateStr}</div>
                        <div><strong style="font-size:0.9rem;">${t.itemNum}</strong><br><span style="font-size:0.8rem;color:#718096;">${t.itemName}</span></div>
                        <div style="font-size:0.85rem;color:#4a5568;">${t.description}</div>
                        <div>${dirBadge}</div>
                        <div style="font-weight:800;color:${qtyColor};font-size:1rem;">${qtySign}${t.qty}</div>
                        <div style="font-size:0.85rem;color:#4a5568;">${t.by && t.by !== '-' ? t.by : '<span style="color:#a0aec0;">—</span>'}</div>
                    </div>
                `;
            }).join('');
        }

        function exportInventoryTransactions() {
            alert('📊 Export feature would generate an Excel/PDF report of all inventory transactions.');
        }

        document.getElementById('txnSearch')?.addEventListener('input', (e) => {
            renderInventoryTransactions(e.target.value.toLowerCase().trim());
        });

        function printItemDetails() {
            alert('?���?Print Item Details\n\nIn a real implementation, this would open a print dialog.');
        }

        // Add inventory form submission
        document.getElementById('addInventoryForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            
            const form = e.target;
            const formData = {
                itemNum:        form.elements.itemNum.value.trim(),
                itemName:       form.elements.itemName.value.trim(),
                longDescription:form.elements.longDescription.value.trim(),
                barcode:        form.elements.barcode.value.trim(),
                qrcode:         form.elements.qrcode.value.trim(),
                commodityGroup: form.elements.commodityGroup.value.trim(),
                stock:          parseInt(form.elements.stock.value) || 0,
                unit:           form.elements.unit.value.trim(),
                price:          parseFloat(form.elements.price.value) || 0,
                minLevel:       parseInt(form.elements.minLevel.value) || 0,
                maxLevel:       parseInt(form.elements.maxLevel.value) || 0,
                reorderQty:     parseInt(form.elements.reorderQty.value) || 0,
                reorderLevel:   parseInt(form.elements.minLevel.value) || 0  // keep compat
            };

            if (currentEditingInventoryItem) {
                const item = inventory.find(i => i.id === currentEditingInventoryItem.id);
                if (item) {
                    Object.assign(item, formData);
                    item.status = item.stock === 0 ? 'out_of_stock'
                                : item.stock <= item.minLevel ? 'low_stock' : 'in_stock';
                    alert(`✅ Item ${formData.itemName} updated successfully!`);
                }
            } else {
                if (inventory.find(i => i.itemNum === formData.itemNum)) {
                    alert('⚠️ An item with this Item Number already exists!');
                    return;
                }
                const newItem = {
                    id: nextInventoryId++,
                    ...formData,
                    status: formData.stock === 0 ? 'out_of_stock'
                          : formData.stock <= formData.minLevel ? 'low_stock' : 'in_stock',
                    lastPhysicalCount: new Date().toISOString().split('T')[0]
                };
                inventory.push(newItem);
                alert(`✅ Item ${formData.itemName} added successfully!`);
            }

            renderInventoryList();
            closeModal('addInventoryModal');
            form.reset();
        });

        // Users database
        let users = [
            { id: 1, name: 'Administrator', username: 'admin', email: 'admin@janoble.com', role: 'admin', status: 'active', createdAt: '2025-01-01' },
            { id: 2, name: 'Staff Member', username: 'staff', email: 'staff@janoble.com', role: 'staff', status: 'active', createdAt: '2025-01-01' },
            { id: 3, name: 'John Doe', username: 'customer', email: 'johndoe@email.com', role: 'customer', status: 'active', createdAt: '2025-03-10' }
        ];
        let nextUserId = 4;
        let currentEditingUser = null;

        function renderUsersList() {
            const search = (document.getElementById('userSearch')?.value || '').toLowerCase();
            const filtered = users.filter(u =>
                u.name.toLowerCase().includes(search) ||
                u.username.toLowerCase().includes(search) ||
                u.email.toLowerCase().includes(search) ||
                u.role.toLowerCase().includes(search)
            );

            // Update stats
            document.getElementById('userStatTotal').textContent = users.length;
            document.getElementById('userStatActive').textContent = users.filter(u => u.status === 'active').length;
            document.getElementById('userStatInactive').textContent = users.filter(u => u.status === 'inactive').length;

            const container = document.getElementById('userCardsList');
            if (!container) return;

            if (filtered.length === 0) {
                container.innerHTML = '<div style="text-align:center;padding:3rem;color:#718096;">No users found.</div>';
                return;
            }

            const roleColors = { admin: '#E31E24', staff: '#38a169', customer: '#3182ce' };
            const roleIcons  = { admin: '👨‍💼', staff: '🔧', customer: '👤' };

            container.innerHTML = filtered.map((u, i) => {
                const color     = roleColors[u.role] || '#718096';
                const icon      = roleIcons[u.role]  || '👤';
                const initials  = u.name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2);
                const statusBg  = u.status === 'active' ? '#c6f6d5' : '#fed7d7';
                const statusClr = u.status === 'active' ? '#276749' : '#742a2a';
                const toggleLbl = u.status === 'active' ? '🔒' : '🔓';
                return `
                <div class="table-row" style="grid-template-columns:40px 1.5fr 1fr 1.5fr 1fr 1fr 140px;align-items:center;">
                    <div style="color:#a0aec0;font-size:0.85rem;">${i + 1}</div>
                    <div style="display:flex;align-items:center;gap:0.75rem;">
                        <div style="background:${color};width:34px;height:34px;border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:0.78rem;font-weight:800;color:white;flex-shrink:0;">${initials}</div>
                        <span style="font-weight:600;color:#1a202c;">${u.name}</span>
                    </div>
                    <div style="color:#4a5568;">@${u.username}</div>
                    <div style="color:#4a5568;font-size:0.9rem;">${u.email}</div>
                    <div><span style="background:${color}22;color:${color};padding:0.3rem 0.75rem;border-radius:20px;font-size:0.78rem;font-weight:700;">${icon} ${u.role.charAt(0).toUpperCase()+u.role.slice(1)}</span></div>
                    <div><span style="background:${statusBg};color:${statusClr};padding:0.3rem 0.75rem;border-radius:20px;font-size:0.78rem;font-weight:700;">${u.status === 'active' ? '✅ Active' : '🔴 Inactive'}</span></div>
                    <div style="display:flex;gap:0.4rem;">
                        <button onclick="viewUser(${u.id})" class="btn-small btn-secondary" title="View">👁</button>
                        <button onclick="editUser(${u.id})" class="btn-small btn-primary" title="Edit">✏️</button>
                        <button onclick="toggleUserStatus(${u.id})" class="btn-small ${u.status==='active'?'btn-danger':'btn-success'}" title="${u.status==='active'?'Deactivate':'Activate'}">${toggleLbl}</button>
                    </div>
                </div>`;
            }).join('');
        }

        function openAddUserModal() {
            currentEditingUser = null;
            document.getElementById('userModalTitle').textContent = 'Add User';
            document.getElementById('userPasswordLabel').textContent = 'Password *';
            document.getElementById('userPasswordInput').required = true;
            document.getElementById('addUserForm').reset();
            // Auto-generate next user ID display (optional)
            document.getElementById('addUserModal').classList.add('active');
        }

        function viewUser(userId) {
            const u = users.find(u => u.id === userId);
            if (!u) return;
            const roleColors = { admin: '#E31E24', staff: '#38a169', customer: '#3182ce' };
            const color = roleColors[u.role] || '#718096';
            const initials = u.name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2);

            document.getElementById('vuHeader').style.background = `linear-gradient(135deg, ${color}, ${color}cc)`;
            document.getElementById('vuAvatar').textContent = initials;
            document.getElementById('vuName').textContent = u.name;
            document.getElementById('vuUsername').textContent = '@' + u.username;
            document.getElementById('vuRoleBadge').innerHTML = `<span style="background:rgba(255,255,255,0.25);padding:0.3rem 0.85rem;border-radius:20px;font-size:0.78rem;font-weight:700;color:white;">${u.role.charAt(0).toUpperCase()+u.role.slice(1)}</span>`;
            document.getElementById('vuStatusBadge').innerHTML = `<span style="background:${u.status==='active'?'rgba(198,246,213,0.3)':'rgba(254,215,215,0.3)'};padding:0.3rem 0.85rem;border-radius:20px;font-size:0.78rem;font-weight:700;color:white;">${u.status==='active'?'✅ Active':'🔴 Inactive'}</span>`;

            document.getElementById('vuInfoGrid').innerHTML = [
                ['✉️ Email', u.email],
                ['📅 Joined', u.createdAt],
                ['🔑 Username', u.username],
                ['🎭 Role', u.role.charAt(0).toUpperCase()+u.role.slice(1)]
            ].map(([label, val]) => `
                <div style="background:#f7fafc;border-radius:10px;padding:0.85rem 1rem;">
                    <div style="font-size:0.72rem;color:#718096;font-weight:700;text-transform:uppercase;letter-spacing:0.4px;margin-bottom:0.3rem;">${label}</div>
                    <div style="font-weight:600;color:#1a202c;font-size:0.9rem;">${val}</div>
                </div>`).join('');

            document.getElementById('vuEditBtn').onclick = () => { closeModal('viewUserModal'); editUser(userId); };
            document.getElementById('viewUserModal').classList.add('active');
        }

        function editUser(userId) {
            const u = users.find(u => u.id === userId);
            if (!u) return;
            currentEditingUser = u;
            document.getElementById('userModalTitle').textContent = 'Edit User';
            document.getElementById('userPasswordLabel').textContent = 'New Password (leave blank to keep current)';
            document.getElementById('userPasswordInput').required = false;

            const form = document.getElementById('addUserForm');
            form.elements.name.value     = u.name;
            form.elements.username.value = u.username;
            form.elements.email.value    = u.email;
            form.elements.role.value     = u.role;
            form.elements.status.value   = u.status;
            form.elements.password.value = '';
            document.getElementById('addUserModal').classList.add('active');
        }

        function toggleUserStatus(userId) {
            const u = users.find(u => u.id === userId);
            if (!u) return;
            const action = u.status === 'active' ? 'deactivate' : 'activate';
            if (confirm(`${action.charAt(0).toUpperCase()+action.slice(1)} user "${u.name}"?`)) {
                u.status = u.status === 'active' ? 'inactive' : 'active';
                renderUsersList();
            }
        }

        function deactivateUser(username) {
            const u = users.find(u => u.username === username);
            if (u) toggleUserStatus(u.id);
        }

        function addUser() { openAddUserModal(); }

        document.getElementById('addUserForm')?.addEventListener('submit', function(e) {
            e.preventDefault();
            const form = e.target;
            const name     = form.elements.name.value.trim();
            const username = form.elements.username.value.trim();
            const email    = form.elements.email.value.trim();
            const role     = form.elements.role.value;
            const status   = form.elements.status.value;
            const password = form.elements.password.value;

            if (currentEditingUser) {
                // Check username uniqueness (excluding self)
                if (users.find(u => u.username === username && u.id !== currentEditingUser.id)) {
                    alert('⚠️ Username already taken by another user.');
                    return;
                }
                Object.assign(currentEditingUser, { name, username, email, role, status });
                alert(`✅ User "${name}" updated successfully!`);
            } else {
                if (users.find(u => u.username === username)) {
                    alert('⚠️ Username already exists.');
                    return;
                }
                if (!password) { alert('⚠️ Password is required for new users.'); return; }
                users.push({
                    id: nextUserId++,
                    name, username, email, role, status,
                    createdAt: new Date().toISOString().split('T')[0]
                });
                alert(`✅ User "${name}" added successfully!`);
            }

            renderUsersList();
            closeModal('addUserModal');
            form.reset();
            currentEditingUser = null;
        });

        // Search functionality
        document.getElementById('assetSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#assetsList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        document.getElementById('inventorySearch')?.addEventListener('input', renderInventoryList);

        document.getElementById('userSearch')?.addEventListener('input', renderUsersList);

        // Staff Inventory Usage Functions
        let currentStaffInventoryItem = null;
        let currentDeliveryItem = null;
        let inventoryUsageRecords = [];
        let deliveryRecords = [];
        window.deliveryRecords = deliveryRecords;

        function renderStaffInventoryList() {
            const staffInventoryList = document.getElementById('staffInventoryList');
            if (!staffInventoryList) return;

            const statusBadges = {
                low_stock: '<span class="status-badge status-overdue">Low Stock</span>',
                in_stock: '<span class="status-badge status-active">In Stock</span>',
                out_of_stock: '<span class="status-badge status-pending">Out of Stock</span>'
            };

            staffInventoryList.innerHTML = inventory.map(item => `
                <div class="table-row">
                    <div>${item.itemName}</div>
                    <div>${item.stock} ${item.unit}</div>
                    <div>${statusBadges[item.status]}</div>
                    <div>
                        <button class="btn-small btn-primary" onclick="viewItemDetails('${item.itemNum}')" title="View">👁️</button>
                        <button class="btn-small btn-secondary" onclick="editStaffInventoryItem('${item.itemNum}')" title="Edit">✏️</button>
                    </div>
                </div>
            `).join('');
        }

        function openStaffAddInventoryModal() {
            openAddInventoryModal(); // Reuse the admin modal
        }

        function editStaffInventoryItem(itemNum) {
            editInventoryItem(itemNum); // Reuse the admin function
        }

        function openStaffReceiveDeliveryModal() {
            document.getElementById('staffReceiveDeliveryModal').classList.add('active');
            document.getElementById('deliveryItemInfo').style.display = 'none';
            document.getElementById('deliveryPreview').style.display = 'none';
            document.getElementById('deliveryItemSearch').value = '';
            document.getElementById('deliveryQuantity').value = '';
            currentDeliveryItem = null;
        }

        function openDeliveryScanModal() {
            document.getElementById('deliveryScanModal').classList.add('active');
            document.getElementById('deliveryScanInput').value = '';
        }

        function searchDeliveryScannedItem() {
            const code = document.getElementById('deliveryScanInput').value.trim();
            if (!code) {
                alert('?��? Please enter a barcode or QR code');
                return;
            }

            const item = inventory.find(i => 
                i.barcode === code || i.qrcode === code
            );

            if (item) {
                closeModal('deliveryScanModal');
                
                currentDeliveryItem = item;
                document.getElementById('deliveryItemSearch').value = item.itemNum;
                document.getElementById('deliveryItemInfo').style.display = 'block';
                document.getElementById('deliveryItemName').textContent = item.itemName;
                document.getElementById('deliveryItemCode').textContent = item.itemNum;
                document.getElementById('deliveryCurrentStock').textContent = `${item.stock} ${item.unit}`;
                document.getElementById('deliveryUnit').textContent = item.unit;
                // Scroll modal body to show item info
                const modalBody = document.querySelector('#staffReceiveDeliveryModal .modal-content');
                if (modalBody) setTimeout(() => modalBody.scrollTo({ top: modalBody.scrollHeight, behavior: 'smooth' }), 50);
                
                alert(`??Item found: ${item.itemName}`);
            } else {
                alert('??No item found with this barcode or QR code');
            }
        }

        // Delivery item search
        document.getElementById('deliveryItemSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.trim().toLowerCase();
            if (searchTerm.length < 3) {
                document.getElementById('deliveryItemInfo').style.display = 'none';
                document.getElementById('deliveryPreview').style.display = 'none';
                currentDeliveryItem = null;
                return;
            }

            const item = inventory.find(i => 
                i.barcode.toLowerCase().includes(searchTerm) ||
                i.qrcode.toLowerCase().includes(searchTerm) ||
                i.itemNum.toLowerCase().includes(searchTerm) ||
                i.itemName.toLowerCase().includes(searchTerm)
            );

            if (item) {
                currentDeliveryItem = item;
                document.getElementById('deliveryItemInfo').style.display = 'block';
                document.getElementById('deliveryItemName').textContent = item.itemName;
                document.getElementById('deliveryItemCode').textContent = item.itemNum;
                document.getElementById('deliveryCurrentStock').textContent = `${item.stock} ${item.unit}`;
                document.getElementById('deliveryUnit').textContent = item.unit;
                // Scroll modal body to show item info
                const modalBody = document.querySelector('#staffReceiveDeliveryModal .modal-content');
                if (modalBody) setTimeout(() => modalBody.scrollTo({ top: modalBody.scrollHeight, behavior: 'smooth' }), 50);
            } else {
                document.getElementById('deliveryItemInfo').style.display = 'none';
                currentDeliveryItem = null;
            }
        });

        // Delivery quantity change
        document.getElementById('deliveryQuantity')?.addEventListener('input', (e) => {
            if (!currentDeliveryItem) return;

            const quantity = parseInt(e.target.value);
            const previewDiv = document.getElementById('deliveryPreview');

            if (!isNaN(quantity) && quantity > 0) {
                const newStock = currentDeliveryItem.stock + quantity;
                previewDiv.style.display = 'block';
                document.getElementById('deliveryPreviewMessage').innerHTML = 
                    `Current Stock: <strong>${currentDeliveryItem.stock} ${currentDeliveryItem.unit}</strong><br>` +
                    `Quantity Received: <strong>+${quantity} ${currentDeliveryItem.unit}</strong><br>` +
                    `New Stock: <strong>${newStock} ${currentDeliveryItem.unit}</strong>`;
                // Scroll modal to bottom to show preview and confirm button
                const modalContent = document.querySelector('#staffReceiveDeliveryModal .modal-content');
                if (modalContent) setTimeout(() => modalContent.scrollTo({ top: modalContent.scrollHeight, behavior: 'smooth' }), 50);
            } else {
                previewDiv.style.display = 'none';
            }
        });

        function submitDeliveryReceived() {
            if (!currentDeliveryItem) {
                alert('?��? Please select an item first');
                return;
            }

            const quantity = parseInt(document.getElementById('deliveryQuantity').value);
            if (isNaN(quantity) || quantity <= 0) {
                alert('?��? Please enter a valid quantity');
                return;
            }

            // Update inventory
            const item = inventory.find(i => i.itemNum === currentDeliveryItem.itemNum);
            if (item) {
                const oldStock = item.stock;
                item.stock += quantity;
                
                // Update status
                if (item.stock === 0) {
                    item.status = 'out_of_stock';
                } else if (item.stock <= item.reorderLevel) {
                    item.status = 'low_stock';
                } else {
                    item.status = 'in_stock';
                }

                // Record delivery
                deliveryRecords.push({
                    date: new Date().toISOString(),
                    itemNum: item.itemNum,
                    itemName: item.itemName,
                    quantityReceived: quantity,
                    previousStock: oldStock,
                    newStock: item.stock,
                    receivedBy: currentUser ? currentUser.name : 'Unknown'
                });

                // Update staff inventory list and admin list
                renderStaffInventoryList();
                renderInventoryList();
                closeModal('staffReceiveDeliveryModal');

                alert(`✅ Update Stock Successfully!\n\nItem: ${item.itemName}\nQuantity Received: ${quantity} ${item.unit}\nPrevious Stock: ${oldStock} ${item.unit}\nNew Stock: ${item.stock} ${item.unit}`);
            }
        }

        function viewStaffInventoryDetails() {
            const modal = document.getElementById('staffViewInventoryModal');
            modal.classList.add('active');
            renderStaffViewInventoryList();
        }

        function renderStaffViewInventoryList() {
            const list = document.getElementById('staffViewInventoryList');
            if (!list) return;

            const statusBadges = {
                low_stock: '<span class="status-badge status-overdue">Low Stock</span>',
                in_stock: '<span class="status-badge status-active">In Stock</span>',
                out_of_stock: '<span class="status-badge status-pending">Out of Stock</span>'
            };

            list.innerHTML = inventory.map(item => `
                <div class="table-row">
                    <div>${item.itemName}</div>
                    <div>${item.itemNum}</div>
                    <div>${item.stock} ${item.unit}</div>
                    <div>${statusBadges[item.status]}</div>
                    <div>
                        <button class="btn-small btn-primary" onclick="viewItemDetails('${item.itemNum}'); closeModal('staffViewInventoryModal');" title="View">👁️</button>
                        <button class="btn-small btn-secondary" onclick="editStaffInventoryItem('${item.itemNum}'); closeModal('staffViewInventoryModal');" title="Edit">✏️</button>
                    </div>
                </div>
            `).join('');
        }

        // Staff view inventory search
        document.getElementById('staffViewInventorySearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#staffViewInventoryList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        // Staff inventory search bar
        document.getElementById('staffInventorySearchBar')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#staffInventoryList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        function openStaffInventoryUsage() {
            document.getElementById('staffInventoryUsageModal').classList.add('active');
            document.getElementById('staffInventoryItemInfo').style.display = 'none';
            document.getElementById('staffUsageWarning').style.display = 'none';
            document.getElementById('staffInventorySearch').value = '';
            document.getElementById('staffUsageQuantity').value = '';
            document.getElementById('staffUsageReason').value = '';
            currentStaffInventoryItem = null;
        }

        function openStaffScanModal() {
            document.getElementById('staffScanModal').classList.add('active');
            document.getElementById('staffScanInput').value = '';
        }

        function searchStaffScannedItem() {
            const code = document.getElementById('staffScanInput').value.trim();
            if (!code) {
                alert('?��? Please enter a barcode or QR code');
                return;
            }

            const item = inventory.find(i => 
                i.barcode === code || i.qrcode === code
            );

            if (item) {
                closeModal('staffScanModal');
                
                currentStaffInventoryItem = item;
                document.getElementById('staffInventorySearch').value = item.itemNum;
                document.getElementById('staffInventoryItemInfo').style.display = 'block';
                document.getElementById('staffItemName').textContent = item.itemName;
                document.getElementById('staffItemCode').textContent = item.itemNum;
                document.getElementById('staffCurrentStock').textContent = `${item.stock} ${item.unit}`;
                document.getElementById('staffUnit').textContent = item.unit;
                
                alert(`??Part found: ${item.itemName}`);
            } else {
                alert('??No part found with this barcode or QR code');
            }
        }

        // Staff inventory search
        document.getElementById('staffInventorySearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.trim().toLowerCase();
            if (searchTerm.length < 3) {
                document.getElementById('staffInventoryItemInfo').style.display = 'none';
                document.getElementById('staffUsageWarning').style.display = 'none';
                currentStaffInventoryItem = null;
                return;
            }

            const item = inventory.find(i => 
                i.barcode.toLowerCase().includes(searchTerm) ||
                i.qrcode.toLowerCase().includes(searchTerm) ||
                i.itemNum.toLowerCase().includes(searchTerm) ||
                i.itemName.toLowerCase().includes(searchTerm)
            );

            if (item) {
                currentStaffInventoryItem = item;
                document.getElementById('staffInventoryItemInfo').style.display = 'block';
                document.getElementById('staffItemName').textContent = item.itemName;
                document.getElementById('staffItemCode').textContent = item.itemNum;
                document.getElementById('staffCurrentStock').textContent = `${item.stock} ${item.unit}`;
                document.getElementById('staffUnit').textContent = item.unit;
            } else {
                document.getElementById('staffInventoryItemInfo').style.display = 'none';
                currentStaffInventoryItem = null;
            }
        });

        // Staff usage quantity change
        document.getElementById('staffUsageQuantity')?.addEventListener('input', (e) => {
            if (!currentStaffInventoryItem) return;

            const quantity = parseInt(e.target.value);
            const warningDiv = document.getElementById('staffUsageWarning');

            if (!isNaN(quantity) && quantity > 0) {
                if (quantity > currentStaffInventoryItem.stock) {
                    warningDiv.style.display = 'block';
                    document.getElementById('staffWarningMessage').textContent = 
                        `Insufficient stock! Only ${currentStaffInventoryItem.stock} ${currentStaffInventoryItem.unit} available.`;
                } else if (currentStaffInventoryItem.stock - quantity <= currentStaffInventoryItem.reorderLevel) {
                    warningDiv.style.display = 'block';
                    warningDiv.style.background = '#fff5e6';
                    warningDiv.style.borderLeft = '4px solid #ff6b35';
                    document.getElementById('staffWarningMessage').style.color = '#8b4513';
                    document.getElementById('staffWarningMessage').textContent = 
                        `After this usage, stock will be ${currentStaffInventoryItem.stock - quantity} ${currentStaffInventoryItem.unit} (below reorder level of ${currentStaffInventoryItem.reorderLevel}).`;
                } else {
                    warningDiv.style.display = 'none';
                }
            } else {
                warningDiv.style.display = 'none';
            }
        });

        function submitStaffInventoryUsage() {
            if (!currentStaffInventoryItem) {
                alert('?��? Please select a part first');
                return;
            }

            const quantity = parseInt(document.getElementById('staffUsageQuantity').value);
            if (isNaN(quantity) || quantity <= 0) {
                alert('?��? Please enter a valid quantity');
                return;
            }

            if (quantity > currentStaffInventoryItem.stock) {
                alert(`??Insufficient stock!\n\nRequested: ${quantity} ${currentStaffInventoryItem.unit}\nAvailable: ${currentStaffInventoryItem.stock} ${currentStaffInventoryItem.unit}`);
                return;
            }

            const reason = document.getElementById('staffUsageReason').value.trim();

            // Update inventory
            const item = inventory.find(i => i.itemNum === currentStaffInventoryItem.itemNum);
            if (item) {
                const oldStock = item.stock;
                item.stock -= quantity;
                
                // Update status
                if (item.stock === 0) {
                    item.status = 'out_of_stock';
                } else if (item.stock <= item.reorderLevel) {
                    item.status = 'low_stock';
                } else {
                    item.status = 'in_stock';
                }

                // Record usage
                inventoryUsageRecords.push({
                    date: new Date().toISOString(),
                    itemNum: item.itemNum,
                    itemName: item.itemName,
                    quantityUsed: quantity,
                    previousStock: oldStock,
                    newStock: item.stock,
                    usedBy: currentUser ? currentUser.name : 'Unknown',
                    reason: reason || 'Not specified'
                });

                // Update staff inventory list
                renderStaffInventoryList();
                closeModal('staffInventoryUsageModal');

                let alertMessage = `??Inventory Updated!\n\n` +
                      `Part: ${item.itemName}\n` +
                      `Quantity Used: ${quantity} ${item.unit}\n` +
                      `Previous Stock: ${oldStock} ${item.unit}\n` +
                      `New Stock: ${item.stock} ${item.unit}\n`;
                
                if (reason) {
                    alertMessage += `Used For: ${reason}\n`;
                }

                if (item.stock <= item.reorderLevel) {
                    alertMessage += `\n?��? WARNING: Stock is now at or below reorder level (${item.reorderLevel} ${item.unit})`;
                }

                alert(alertMessage);
            }
        }

        // Close modal when clicking outside
        document.querySelectorAll('.modal').forEach(modal => {
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    modal.classList.remove('active');
                }
            });
        });

        // ========================================
        // PMS MANAGEMENT FUNCTIONS
        // ========================================

        let pmsRecords = [];
        let nextPMSId = 1;

        // Render PMS Management List
        function renderPMSManagementList() {
            const list = document.getElementById('pmsManagementList');
            if (!list) return;

            if (pmsRecords.length === 0) {
                list.innerHTML = '<div class="table-row" style="text-align: center; color: #718096; padding: 2rem;">No PMS schedules created yet. Click "Add PMS Schedule" to create one.</div>';
                updatePMSManagementStats();
                return;
            }

            const statusBadges = {
                pending: '<span class="status-badge status-pending">Pending</span>',
                'in progress': '<span class="status-badge status-active">In Progress</span>',
                completed: '<span class="status-badge status-completed">Completed</span>'
            };

            const priorityBadges = {
                Low: '<span style="background: #bee3f8; color: #1a365d; padding: 0.2rem 0.6rem; border-radius: 4px; font-size: 0.8rem;">Low</span>',
                Medium: '<span style="background: #feebc8; color: #7c2d12; padding: 0.2rem 0.6rem; border-radius: 4px; font-size: 0.8rem;">Medium</span>',
                High: '<span style="background: #fed7d7; color: #742a2a; padding: 0.2rem 0.6rem; border-radius: 4px; font-size: 0.8rem;">High</span>'
            };

            list.innerHTML = pmsRecords.map(pms => {
                let intervalText = '';
                if (pms.maintenanceBasis === 'date') {
                    intervalText = `${pms.intervalValue} ${pms.intervalType}`;
                } else if (pms.maintenanceBasis === 'usage') {
                    intervalText = `Every ${pms.maintenanceEvery} ${pms.meterUnit}`;
                }

                return `
                    <div class="table-row">
                        <div><strong>${pms.assetNum}</strong></div>
                        <div>${pms.assetName}</div>
                        <div style="font-size: 0.85rem;">${intervalText}</div>
                        <div><strong>${pms.nextDueDate ? new Date(pms.nextDueDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A'}</strong></div>
                        <div>${pms.assignedMechanic}</div>
                        <div>${statusBadges[pms.status] || statusBadges['pending']}</div>
                        <div>
                            <button class="btn-small btn-primary" onclick="viewPMSRecord(${pms.id})" title="View">👁️</button>
                            <button class="btn-small btn-secondary" onclick="editPMSRecord(${pms.id})" title="Edit">✏️</button>
                            <button class="btn-small btn-warning" onclick="updatePMSStatus(${pms.id})" title="Update Status">🔄</button>
                            <button class="btn-small btn-danger" onclick="deletePMSRecord(${pms.id})" title="Delete">🗑️</button>
                        </div>
                    </div>
                `;
            }).join('');

            updatePMSManagementStats();
        }

        // Update PMS Management Statistics
        function updatePMSManagementStats() {
            const today = new Date();
            const endOfMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0);

            document.getElementById('totalPMSRecords').textContent = pmsRecords.length;
            
            const dueThisMonth = pmsRecords.filter(pms => {
                if (pms.nextDueDate) {
                    const dueDate = new Date(pms.nextDueDate);
                    return dueDate >= today && dueDate <= endOfMonth;
                }
                return false;
            }).length;
            document.getElementById('pmsDueCount').textContent = dueThisMonth;
            
            document.getElementById('pmsActiveCount').textContent = pmsRecords.filter(pms => pms.status === 'active').length;
            document.getElementById('pmsCompletedCount').textContent = pmsRecords.filter(pms => pms.status === 'completed').length;
        }

        // Open Add PMS Modal
        function openAddPMSModal() {
            document.getElementById('addPMSModal').classList.add('active');
            document.getElementById('pmsModalTitle').textContent = 'Add PMS Schedule';
            document.getElementById('addPMSForm').reset();
            
            // Populate asset dropdown
            const assetSelect = document.getElementById('pmsAssetSelect');
            assetSelect.innerHTML = '<option value="">Select Asset</option>' + 
                assets.map(asset => `<option value="${asset.assetNum}">${asset.assetNum}</option>`).join('');
            
            // Set default planned schedule date to today
            const plannedDateInput = document.querySelector('[name="plannedScheduleDate"]');
            plannedDateInput.value = new Date().toISOString().split('T')[0];
            
            updatePMSBasisFields();
        }

        // Load PMS Asset Details
        function loadPMSAssetDetails() {
            const assetNum = document.getElementById('pmsAssetSelect').value;
            
            if (!assetNum) {
                document.getElementById('pmsAssetName').value = '';
                document.getElementById('pmsAssetOwner').value = '';
                document.getElementById('pmsMeterTypeSelect').innerHTML = '<option value="">Select Meter</option>';
                return;
            }

            const asset = assets.find(a => a.assetNum === assetNum);
            if (asset) {
                document.getElementById('pmsAssetName').value = asset.assetDescription || 'N/A';
                document.getElementById('pmsAssetOwner').value = asset.owner || 'N/A';
                
                // Populate meter types if asset has meters
                const meterSelect = document.getElementById('pmsMeterTypeSelect');
                if (asset.meters && asset.meters.length > 0) {
                    meterSelect.innerHTML = '<option value="">Select Meter</option>' +
                        asset.meters.map(meter => `<option value="${meter.name}" data-value="${meter.value}" data-unit="${meter.unit}">${meter.name}</option>`).join('');
                } else {
                    meterSelect.innerHTML = '<option value="">No meters available</option>';
                }
            }
        }

        // Update PMS Basis Fields
        function updatePMSBasisFields() {
            const basis = document.getElementById('pmsMaintenanceBasis').value;
            const dateFields = document.getElementById('pmsDateBasedFields');
            const usageFields = document.getElementById('pmsUsageBasedFields');

            if (basis === 'date') {
                dateFields.style.display = 'block';
                usageFields.style.display = 'none';
            } else if (basis === 'usage') {
                dateFields.style.display = 'none';
                usageFields.style.display = 'block';
                
                // Load meter details when switching to usage-based
                const meterSelect = document.getElementById('pmsMeterTypeSelect');
                if (meterSelect.value) {
                    const selectedOption = meterSelect.options[meterSelect.selectedIndex];
                    document.getElementById('pmsCurrentMeterReading').value = selectedOption.dataset.value || '';
                    document.getElementById('pmsMeterUnit').value = selectedOption.dataset.unit || '';
                }
            } else {
                dateFields.style.display = 'none';
                usageFields.style.display = 'none';
            }
        }

        // Update meter reading when meter type changes
        document.getElementById('pmsMeterTypeSelect')?.addEventListener('change', (e) => {
            const selectedOption = e.target.options[e.target.selectedIndex];
            document.getElementById('pmsCurrentMeterReading').value = selectedOption.dataset.value || '';
            document.getElementById('pmsMeterUnit').value = selectedOption.dataset.unit || '';
        });

        // Calculate Next Due Date
        function calculateNextDueDate() {
            const intervalType = document.querySelector('[name="intervalType"]').value;
            const intervalValue = parseInt(document.querySelector('[name="intervalValue"]').value);
            const startDate = document.querySelector('[name="startDate"]').value;

            if (!intervalType || !intervalValue || !startDate) {
                document.getElementById('pmsNextDueDate').value = '';
                return;
            }

            const start = new Date(startDate);
            let nextDue = new Date(start);

            switch(intervalType) {
                case 'Monthly':
                    nextDue.setMonth(nextDue.getMonth() + intervalValue);
                    break;
                case 'Quarterly':
                    nextDue.setMonth(nextDue.getMonth() + (intervalValue * 3));
                    break;
                case 'Semi-Annually':
                    nextDue.setMonth(nextDue.getMonth() + (intervalValue * 6));
                    break;
                case 'Yearly':
                    nextDue.setFullYear(nextDue.getFullYear() + intervalValue);
                    break;
            }

            document.getElementById('pmsNextDueDate').value = nextDue.toISOString().split('T')[0];
        }

        // View PMS Record
        function viewPMSRecord(id) {
            const pms = pmsRecords.find(p => p.id === id);
            if (!pms) return;

            let scheduleDetails = '';
            if (pms.maintenanceBasis === 'date') {
                scheduleDetails = `Schedule Type: Date-Based\n` +
                    `Interval: ${pms.intervalValue} ${pms.intervalType}\n` +
                    `Start Date: ${new Date(pms.startDate).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}\n` +
                    `Next Due Date: ${new Date(pms.nextDueDate).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}`;
            } else if (pms.maintenanceBasis === 'usage') {
                scheduleDetails = `Schedule Type: Usage-Based\n` +
                    `Meter Type: ${pms.meterType}\n` +
                    `Current Reading: ${pms.currentMeterReading} ${pms.meterUnit}\n` +
                    `Maintenance Every: ${pms.maintenanceEvery} ${pms.meterUnit}`;
            }

            alert(`?? PMS SCHEDULE DETAILS\n\n` +
                  `Asset Number: ${pms.assetNum}\n` +
                  `Asset Name: ${pms.assetName}\n` +
                  `Location: ${pms.location}\n` +
                  `Maintenance Type: ${pms.maintenanceType}\n` +
                  `Priority Level: ${pms.priorityLevel}\n\n` +
                  `SCHEDULE SETTINGS:\n` +
                  `${scheduleDetails}\n\n` +
                  `ASSIGNMENT:\n` +
                  `Assigned Mechanic: ${pms.assignedMechanic}\n` +
                  `Supervisor: ${pms.supervisor}\n` +
                  `Planned Schedule Date: ${new Date(pms.plannedScheduleDate).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}\n\n` +
                  `Status: ${pms.status.toUpperCase()}\n` +
                  `Notes: ${pms.notes || 'None'}\n\n` +
                  `Created By: ${pms.createdBy}\n` +
                  `Created On: ${new Date(pms.createdOn).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}`);
        }

        // Edit PMS Record
        function editPMSRecord(id) {
            const pms = pmsRecords.find(p => p.id === id);
            if (!pms) return;

            document.getElementById('addPMSModal').classList.add('active');
            document.getElementById('pmsModalTitle').textContent = 'Edit PMS Schedule';

            const form = document.getElementById('addPMSForm');
            
            // Populate asset dropdown
            const assetSelect = document.getElementById('pmsAssetSelect');
            assetSelect.innerHTML = '<option value="">Select Asset</option>' + 
                assets.map(asset => `<option value="${asset.assetNum}">${asset.assetNum}</option>`).join('');
            assetSelect.value = pms.assetNum;
            
            loadPMSAssetDetails();
            
            form.elements.maintenanceType.value = pms.maintenanceType;
            form.elements.priorityLevel.value = pms.priorityLevel;
            form.elements.maintenanceBasis.value = pms.maintenanceBasis;
            
            updatePMSBasisFields();

            if (pms.maintenanceBasis === 'date') {
                form.elements.intervalType.value = pms.intervalType;
                form.elements.intervalValue.value = pms.intervalValue;
                form.elements.startDate.value = pms.startDate;
                document.getElementById('pmsNextDueDate').value = pms.nextDueDate;
            } else if (pms.maintenanceBasis === 'usage') {
                form.elements.meterType.value = pms.meterType;
                document.getElementById('pmsCurrentMeterReading').value = pms.currentMeterReading;
                form.elements.maintenanceEvery.value = pms.maintenanceEvery;
                document.getElementById('pmsMeterUnit').value = pms.meterUnit;
            }

            form.elements.assignedMechanic.value = pms.assignedMechanic;
            form.elements.supervisor.value = pms.supervisor;
            form.elements.plannedScheduleDate.value = pms.plannedScheduleDate;
            form.elements.notes.value = pms.notes || '';

            form.dataset.editingId = id;
        }

        // Delete PMS Record
        function deletePMSRecord(id) {
            const pms = pmsRecords.find(p => p.id === id);
            if (!pms) return;

            if (confirm(`?��? Are you sure you want to delete this PMS schedule?\n\nAsset: ${pms.assetNum} - ${pms.assetName}\nMaintenance Type: ${pms.maintenanceType}\n\nThis action cannot be undone.`)) {
                pmsRecords = pmsRecords.filter(p => p.id !== id);
                renderPMSManagementList();
                alert('??PMS schedule deleted successfully.');
            }
        }

        // Update PMS Status
        function updatePMSStatus(id) {
            const pms = pmsRecords.find(p => p.id === id);
            if (!pms) return;

            const statusOptions = ['pending', 'in progress', 'completed'];
            const currentIndex = statusOptions.indexOf(pms.status);
            const nextIndex = (currentIndex + 1) % statusOptions.length;
            const newStatus = statusOptions[nextIndex];

            if (confirm(`Update status for Asset ${pms.assetNum}?\n\nCurrent: ${pms.status}\nNew: ${newStatus}`)) {
                pms.status = newStatus;
                renderPMSManagementList();
                alert(`??Status updated to: ${newStatus}`);
            }
        }

        // PMS Form Submission
        document.getElementById('addPMSForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            
            const form = e.target;
            const editingId = form.dataset.editingId ? parseInt(form.dataset.editingId) : null;

            const pmsData = {
                id: editingId || nextPMSId++,
                assetNum: form.elements.assetNum.value,
                assetName: document.getElementById('pmsAssetName').value,
                maintenanceType: form.elements.maintenanceType ? form.elements.maintenanceType.value : '',
                priorityLevel: form.elements.priorityLevel ? form.elements.priorityLevel.value : '',
                maintenanceBasis: form.elements.maintenanceBasis.value,
                assignedMechanic: form.elements.assignedMechanic.value,
                supervisor: form.elements.supervisor ? form.elements.supervisor.value : '',
                plannedScheduleDate: form.elements.plannedScheduleDate.value,
                notes: form.elements.notes ? form.elements.notes.value.trim() : '',
                status: 'pending',
                createdBy: currentUser ? currentUser.name : 'Unknown',
                createdOn: new Date().toISOString()
            };

            if (pmsData.maintenanceBasis === 'date') {
                pmsData.intervalType = form.elements.intervalType.value;
                pmsData.intervalValue = parseInt(form.elements.intervalValue.value);
                pmsData.startDate = form.elements.startDate.value;
                pmsData.nextDueDate = document.getElementById('pmsNextDueDate').value;
            } else if (pmsData.maintenanceBasis === 'usage') {
                pmsData.meterType = form.elements.meterType.value;
                pmsData.currentMeterReading = document.getElementById('pmsCurrentMeterReading').value;
                pmsData.maintenanceEvery = parseInt(form.elements.maintenanceEvery.value);
                pmsData.meterUnit = document.getElementById('pmsMeterUnit').value;
            }

            if (editingId) {
                const existingPMS = pmsRecords.find(p => p.id === editingId);
                if (existingPMS) {
                    Object.assign(existingPMS, pmsData);
                    alert(`??PMS schedule updated successfully!`);
                }
            } else {
                pmsRecords.push(pmsData);
                alert(`??PMS schedule created successfully!\n\nAsset: ${pmsData.assetNum}\nAssigned to: ${pmsData.assignedMechanic}`);
            }

            renderPMSManagementList();
            closeModal('addPMSModal');
            form.reset();
            delete form.dataset.editingId;
        });

        // PMS Management Search
        document.getElementById('pmsManagementSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#pmsManagementList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        // ========================================
        // PMS (Preventive Maintenance Services) Module
        // ========================================

        let pmsTemplates = [];
        let nextPMSTemplateId = 1;
        let pmsSchedules = [];
        let nextPMSScheduleId = 1;

        // Toggle PMS submenu
        function togglePMSSubmenu(event) {
            event.stopPropagation();
            const submenu = document.getElementById('pmsSubmenu');
            const isHidden = submenu.style.display === 'none';
            submenu.style.display = isHidden ? 'block' : 'none';

            // Update arrow icon
            const arrow = event.currentTarget.querySelector('span:last-child');
            if (arrow) {
                arrow.textContent = isHidden ? '▲' : '▼';
            }
        }

        // Update PMS trigger fields based on selection
        function updatePMSTriggerFields() {
            const triggerType = document.getElementById('pmsTriggerType').value;
            const meterFields = document.getElementById('pmsMeterFields');
            const timeFields = document.getElementById('pmsTimeFields');

            if (triggerType === 'meter') {
                meterFields.style.display = 'block';
                timeFields.style.display = 'none';
            } else if (triggerType === 'time') {
                meterFields.style.display = 'none';
                timeFields.style.display = 'block';
            } else if (triggerType === 'both') {
                meterFields.style.display = 'block';
                timeFields.style.display = 'block';
            } else {
                meterFields.style.display = 'none';
                timeFields.style.display = 'none';
            }
        }

        // Open Add PMS Template Modal
        function openAddPMSTemplateModal() {
            document.getElementById('addPMSTemplateModal').classList.add('active');
            document.getElementById('pmsTemplateModalTitle').textContent = 'Create PMS Template';
            document.getElementById('addPMSTemplateForm').reset();
            updatePMSTriggerFields();
        }

        // Render PMS Templates List
        function renderPMSTemplatesList() {
            const list = document.getElementById('pmsTemplatesList');
            if (!list) return;

            if (pmsTemplates.length === 0) {
                list.innerHTML = '<div class="table-row" style="text-align: center; color: #718096; padding: 2rem;">No PMS templates created yet. Click "Create Template" to add one.</div>';
                updatePMSTemplateStats();
                return;
            }

            const statusBadges = {
                active: '<span class="status-badge status-active">Active</span>',
                inactive: '<span class="status-badge status-pending">Inactive</span>'
            };

            list.innerHTML = pmsTemplates.map(template => {
                let intervalText = '';
                if (template.triggerType === 'meter') {
                    intervalText = `Every ${template.meterInterval} ${template.meterType}`;
                } else if (template.triggerType === 'time') {
                    intervalText = `Every ${template.timeInterval} ${template.timeIntervalType}`;
                } else if (template.triggerType === 'both') {
                    intervalText = `${template.meterInterval} ${template.meterType} or ${template.timeInterval} ${template.timeIntervalType}`;
                }

                let leadTimeText = '';
                if (template.triggerType === 'meter' || template.triggerType === 'both') {
                    leadTimeText = `${template.meterLeadTime || 0} units`;
                }
                if (template.triggerType === 'time' || template.triggerType === 'both') {
                    if (leadTimeText) leadTimeText += ' / ';
                    leadTimeText += `${template.timeLeadTime || 0} days`;
                }

                const totalCost = (parseFloat(template.laborCost) || 0) + (parseFloat(template.partsCost) || 0);

                return `
                    <div class="table-row">
                        <div><strong>${template.pmsCode}</strong></div>
                        <div>${template.pmsName}</div>
                        <div><span style="background: #ebf8ff; color: #2c5282; padding: 0.2rem 0.6rem; border-radius: 4px; font-size: 0.8rem;">${template.triggerType}</span></div>
                        <div style="font-size: 0.85rem;">${intervalText}</div>
                        <div style="font-size: 0.85rem;">${leadTimeText}</div>
                        <div><strong>₱${totalCost.toLocaleString('en-PH', {minimumFractionDigits: 2})}</strong></div>
                        <div>${statusBadges[template.status]}</div>
                        <div>
                            <button class="btn-small btn-primary" onclick="viewPMSTemplate(${template.id})" title="View">👁️</button>
                            <button class="btn-small btn-secondary" onclick="editPMSTemplate(${template.id})" title="Edit">✏️</button>
                            <button class="btn-small btn-danger" onclick="deletePMSTemplate(${template.id})" title="Delete">🗑️</button>
                        </div>
                    </div>
                `;
            }).join('');

            updatePMSTemplateStats();
        }

        // Update PMS Template Statistics
        function updatePMSTemplateStats() {
            document.getElementById('totalPMSTemplates').textContent = pmsTemplates.length;
            document.getElementById('activePMSTemplates').textContent = pmsTemplates.filter(t => t.status === 'active').length;
            document.getElementById('meterBasedTemplates').textContent = pmsTemplates.filter(t => t.triggerType === 'meter' || t.triggerType === 'both').length;
            document.getElementById('timeBasedTemplates').textContent = pmsTemplates.filter(t => t.triggerType === 'time' || t.triggerType === 'both').length;
        }

        // View PMS Template Details
        function viewPMSTemplate(id) {
            const template = pmsTemplates.find(t => t.id === id);
            if (!template) return;

            let triggerDetails = '';
            if (template.triggerType === 'meter') {
                triggerDetails = `Meter-Based:\n  Type: ${template.meterType}\n  Interval: Every ${template.meterInterval} units\n  Lead Time: ${template.meterLeadTime || 0} units before due`;
            } else if (template.triggerType === 'time') {
                triggerDetails = `Time-Based:\n  Interval: Every ${template.timeInterval} ${template.timeIntervalType}\n  Lead Time: ${template.timeLeadTime || 0} days before due`;
            } else if (template.triggerType === 'both') {
                triggerDetails = `Combined Trigger:\n  Meter: ${template.meterInterval} ${template.meterType} (Lead: ${template.meterLeadTime || 0})\n  Time: ${template.timeInterval} ${template.timeIntervalType} (Lead: ${template.timeLeadTime || 0} days)`;
            }

            const totalCost = (parseFloat(template.laborCost) || 0) + (parseFloat(template.partsCost) || 0);

            alert(`?? PMS TEMPLATE DETAILS\n\n` +
                  `PMS Number: ${template.pmsCode}\n` +
                  `PMS Name: ${template.pmsName}\n` +
                  `Description: ${template.description || 'N/A'}\n\n` +
                  `TRIGGER CONFIGURATION:\n` +
                  `${triggerDetails}\n\n` +
                  `COST DETAILS:\n` +
                  `Labor Cost: ₱${(parseFloat(template.laborCost) || 0).toLocaleString('en-PH', {minimumFractionDigits: 2})}\n` +
                  `Parts Cost: ₱${(parseFloat(template.partsCost) || 0).toLocaleString('en-PH', {minimumFractionDigits: 2})}\n` +
                  `Total Estimated Cost: ₱${totalCost.toLocaleString('en-PH', {minimumFractionDigits: 2})}\n\n` +
                  `STANDARD SERVICES:\n${template.standardServices || 'Not specified'}\n\n` +
                  `STANDARD PARTS:\n${template.standardParts || 'Not specified'}\n\n` +
                  `Status: ${template.status.toUpperCase()}`);
        }

        // Edit PMS Template
        function editPMSTemplate(id) {
            const template = pmsTemplates.find(t => t.id === id);
            if (!template) return;

            document.getElementById('addPMSTemplateModal').classList.add('active');
            document.getElementById('pmsTemplateModalTitle').textContent = 'Edit PMS Template';

            const form = document.getElementById('addPMSTemplateForm');
            form.elements.pmsCode.value = template.pmsCode;
            form.elements.pmsName.value = template.pmsName;
            form.elements.description.value = template.description || '';
            form.elements.triggerType.value = template.triggerType;
            
            updatePMSTriggerFields();

            if (template.triggerType === 'meter' || template.triggerType === 'both') {
                form.elements.meterType.value = template.meterType || '';
                form.elements.meterInterval.value = template.meterInterval || '';
                form.elements.meterLeadTime.value = template.meterLeadTime || '';
            }

            if (template.triggerType === 'time' || template.triggerType === 'both') {
                form.elements.timeIntervalType.value = template.timeIntervalType || '';
                form.elements.timeInterval.value = template.timeInterval || '';
                form.elements.timeLeadTime.value = template.timeLeadTime || '';
            }

            form.elements.laborCost.value = template.laborCost || '';
            form.elements.partsCost.value = template.partsCost || '';
            form.elements.standardServices.value = template.standardServices || '';
            form.elements.standardParts.value = template.standardParts || '';
            form.elements.status.value = template.status;

            form.dataset.editingId = id;
        }

        // Delete PMS Template
        function deletePMSTemplate(id) {
            const template = pmsTemplates.find(t => t.id === id);
            if (!template) return;

            if (confirm(`?��? Are you sure you want to delete this PMS template?\n\nPMS Number: ${template.pmsCode}\nPMS Name: ${template.pmsName}\n\nThis action cannot be undone.`)) {
                pmsTemplates = pmsTemplates.filter(t => t.id !== id);
                renderPMSTemplatesList();
                alert('??PMS template deleted successfully.');
            }
        }

        // PMS Template Form Submission
        document.getElementById('addPMSTemplateForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            
            const form = e.target;
            const editingId = form.dataset.editingId ? parseInt(form.dataset.editingId) : null;

            const templateData = {
                id: editingId || nextPMSTemplateId++,
                pmsCode: form.elements.pmsCode.value.trim(),
                pmsName: form.elements.pmsName.value.trim(),
                description: form.elements.description.value.trim(),
                triggerType: form.elements.triggerType.value,
                meterType: form.elements.meterType?.value || null,
                meterInterval: form.elements.meterInterval?.value ? parseInt(form.elements.meterInterval.value) : null,
                meterLeadTime: form.elements.meterLeadTime?.value ? parseInt(form.elements.meterLeadTime.value) : null,
                timeIntervalType: form.elements.timeIntervalType?.value || null,
                timeInterval: form.elements.timeInterval?.value ? parseInt(form.elements.timeInterval.value) : null,
                timeLeadTime: form.elements.timeLeadTime?.value ? parseInt(form.elements.timeLeadTime.value) : null,
                laborCost: form.elements.laborCost.value ? parseFloat(form.elements.laborCost.value) : 0,
                partsCost: form.elements.partsCost.value ? parseFloat(form.elements.partsCost.value) : 0,
                standardServices: form.elements.standardServices.value.trim(),
                standardParts: form.elements.standardParts.value.trim(),
                status: form.elements.status.value,
                createdBy: currentUser ? currentUser.name : 'Unknown',
                createdOn: new Date().toISOString()
            };

            if (editingId) {
                const existingTemplate = pmsTemplates.find(t => t.id === editingId);
                if (existingTemplate) {
                    Object.assign(existingTemplate, templateData);
                    alert(`??PMS Template "${templateData.pmsName}" updated successfully!`);
                }
            } else {
                // Check if PMS number already exists
                if (pmsTemplates.find(t => t.pmsCode === templateData.pmsCode)) {
                    alert('??A PMS template with this number already exists!');
                    return;
                }

                pmsTemplates.push(templateData);
                alert(`??PMS Template "${templateData.pmsName}" created successfully!`);
            }

            renderPMSTemplatesList();
            generatePMSSchedules(); // Auto-generate schedules for assets
            closeModal('addPMSTemplateModal');
            form.reset();
            delete form.dataset.editingId;
        });

        // Generate PMS Schedules for Assets
        function generatePMSSchedules() {
            // Clear existing schedules
            pmsSchedules = [];

            // For each active PMS template
            pmsTemplates.filter(t => t.status === 'active').forEach(template => {
                // For each asset
                assets.forEach(asset => {
                    // Check if asset has the required meter for meter-based PMS
                    if (template.triggerType === 'meter' || template.triggerType === 'both') {
                        const hasMeter = asset.meters && asset.meters.some(m => m.name === template.meterType);
                        if (hasMeter) {
                            const meter = asset.meters.find(m => m.name === template.meterType);
                            const currentValue = parseFloat(meter.value) || 0;
                            const dueAt = currentValue + template.meterInterval;
                            const alertAt = dueAt - (template.meterLeadTime || 0);

                            pmsSchedules.push({
                                id: nextPMSScheduleId++,
                                assetNum: asset.assetNum,
                                assetDescription: asset.assetDescription,
                                pmsTemplateId: template.id,
                                pmsCode: template.pmsCode,
                                pmsName: template.pmsName,
                                triggerType: 'meter',
                                meterType: template.meterType,
                                currentValue: currentValue,
                                dueAt: dueAt,
                                alertAt: alertAt,
                                status: currentValue >= dueAt ? 'overdue' : (currentValue >= alertAt ? 'due_soon' : 'upcoming'),
                                lastCompleted: null
                            });
                        }
                    }

                    // For time-based PMS
                    if (template.triggerType === 'time' || template.triggerType === 'both') {
                        const lastServiceDate = asset.lastServiceDate ? new Date(asset.lastServiceDate) : new Date(asset.dateAcquired);
                        const dueDate = calculateDueDate(lastServiceDate, template.timeInterval, template.timeIntervalType);
                        const alertDate = new Date(dueDate);
                        alertDate.setDate(alertDate.getDate() - (template.timeLeadTime || 0));

                        const today = new Date();
                        let status = 'upcoming';
                        if (today >= dueDate) {
                            status = 'overdue';
                        } else if (today >= alertDate) {
                            status = 'due_soon';
                        }

                        pmsSchedules.push({
                            id: nextPMSScheduleId++,
                            assetNum: asset.assetNum,
                            assetDescription: asset.assetDescription,
                            pmsTemplateId: template.id,
                            pmsCode: template.pmsCode,
                            pmsName: template.pmsName,
                            triggerType: 'time',
                            dueDate: dueDate.toISOString().split('T')[0],
                            alertDate: alertDate.toISOString().split('T')[0],
                            status: status,
                            lastCompleted: asset.lastServiceDate
                        });
                    }
                });
            });

            renderPMSScheduleList();
        }

        // Calculate due date based on interval
        function calculateDueDate(startDate, interval, intervalType) {
            const date = new Date(startDate);
            
            switch(intervalType) {
                case 'days':
                    date.setDate(date.getDate() + interval);
                    break;
                case 'weeks':
                    date.setDate(date.getDate() + (interval * 7));
                    break;
                case 'months':
                    date.setMonth(date.getMonth() + interval);
                    break;
                case 'years':
                    date.setFullYear(date.getFullYear() + interval);
                    break;
            }
            
            return date;
        }

        // Render PMS Schedule List
        function renderPMSScheduleList() {
            const list = document.getElementById('pmsScheduleList');
            if (!list) return;

            if (pmsSchedules.length === 0) {
                list.innerHTML = '<div class="table-row" style="text-align: center; color: #718096; padding: 2rem;">No PMS schedules generated yet. Create PMS templates and they will be automatically scheduled for assets.</div>';
                updatePMSScheduleStats();
                return;
            }

            const statusBadges = {
                overdue: '<span class="status-badge status-overdue">Overdue</span>',
                due_soon: '<span class="status-badge status-pending">Due Soon</span>',
                upcoming: '<span class="status-badge status-active">Upcoming</span>',
                completed: '<span class="status-badge status-completed">Completed</span>'
            };

            list.innerHTML = pmsSchedules.map(schedule => {
                let triggerInfo = '';
                let currentInfo = '';
                let dueInfo = '';

                if (schedule.triggerType === 'meter') {
                    triggerInfo = `${schedule.meterType}`;
                    currentInfo = `${schedule.currentValue.toLocaleString()}`;
                    dueInfo = `${schedule.dueAt.toLocaleString()}`;
                } else if (schedule.triggerType === 'time') {
                    triggerInfo = 'Time-Based';
                    currentInfo = new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
                    dueInfo = new Date(schedule.dueDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
                }

                return `
                    <div class="table-row">
                        <div><strong>${schedule.assetNum}</strong><br><small style="color: #718096; font-size: 0.8rem;">${schedule.assetDescription}</small></div>
                        <div>${schedule.pmsName}</div>
                        <div style="font-size: 0.85rem;">${triggerInfo}</div>
                        <div>${currentInfo}</div>
                        <div><strong>${dueInfo}</strong></div>
                        <div>${schedule.dueDate || '-'}</div>
                        <div>${statusBadges[schedule.status]}</div>
                        <div>
                            <button class="btn-small btn-success" onclick="completePMS(${schedule.id})" title="Mark Complete">✅</button>
                            <button class="btn-small btn-primary" onclick="viewPMSSchedule(${schedule.id})" title="View">👁️</button>
                        </div>
                    </div>
                `;
            }).join('');

            updatePMSScheduleStats();
        }

        // Update PMS Schedule Statistics
        function updatePMSScheduleStats() {
            const today = new Date();
            const weekFromNow = new Date();
            weekFromNow.setDate(weekFromNow.getDate() + 7);

            document.getElementById('dueThisWeek').textContent = pmsSchedules.filter(s => {
                if (s.triggerType === 'time' && s.dueDate) {
                    const dueDate = new Date(s.dueDate);
                    return dueDate >= today && dueDate <= weekFromNow;
                }
                return s.status === 'due_soon';
            }).length;

            document.getElementById('overduePMS').textContent = pmsSchedules.filter(s => s.status === 'overdue').length;
            document.getElementById('upcomingPMS').textContent = pmsSchedules.filter(s => s.status === 'upcoming').length;
            
            // Count completed this month (would need completion tracking)
            document.getElementById('completedThisMonth').textContent = 0;
        }

        // View PMS Schedule Details
        function viewPMSSchedule(id) {
            const schedule = pmsSchedules.find(s => s.id === id);
            if (!schedule) return;

            const template = pmsTemplates.find(t => t.id === schedule.pmsTemplateId);
            
            let details = `?? PMS SCHEDULE DETAILS\n\n`;
            details += `Asset: ${schedule.assetNum} - ${schedule.assetDescription}\n`;
            details += `PMS: ${schedule.pmsName} (${schedule.pmsCode})\n`;
            details += `Status: ${schedule.status.toUpperCase().replace('_', ' ')}\n\n`;

            if (schedule.triggerType === 'meter') {
                details += `METER-BASED TRIGGER:\n`;
                details += `Meter Type: ${schedule.meterType}\n`;
                details += `Current Value: ${schedule.currentValue.toLocaleString()}\n`;
                details += `Due At: ${schedule.dueAt.toLocaleString()}\n`;
                details += `Alert At: ${schedule.alertAt.toLocaleString()}\n`;
            } else if (schedule.triggerType === 'time') {
                details += `TIME-BASED TRIGGER:\n`;
                details += `Due Date: ${new Date(schedule.dueDate).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}\n`;
                details += `Alert Date: ${new Date(schedule.alertDate).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}\n`;
            }

            if (template) {
                const totalCost = (parseFloat(template.laborCost) || 0) + (parseFloat(template.partsCost) || 0);
                details += `\nESTIMATED COST: ₱${totalCost.toLocaleString('en-PH', {minimumFractionDigits: 2})}\n`;
                details += `\nSTANDARD SERVICES:\n${template.standardServices || 'Not specified'}`;
            }

            alert(details);
        }

        // Complete PMS
        function completePMS(id) {
            const schedule = pmsSchedules.find(s => s.id === id);
            if (!schedule) return;

            if (confirm(`??Mark this PMS as complete?\n\nAsset: ${schedule.assetNum}\nPMS: ${schedule.pmsName}\n\nThis will update the asset's last service date and reschedule the next PMS.`)) {
                // Update asset last service date
                const asset = assets.find(a => a.assetNum === schedule.assetNum);
                if (asset) {
                    asset.lastServiceDate = new Date().toISOString().split('T')[0];
                }

                // Remove completed schedule
                pmsSchedules = pmsSchedules.filter(s => s.id !== id);

                // Regenerate schedules
                generatePMSSchedules();

                alert(`??PMS completed successfully!\n\nThe next PMS has been scheduled automatically.`);
            }
        }

        // PMS Template Search
        document.getElementById('pmsTemplateSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#pmsTemplatesList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        // PMS Schedule Search
        document.getElementById('pmsScheduleSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#pmsScheduleList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        // Update section titles for PMS subsections
        const originalSwitchAdminSection = switchAdminSection;
        switchAdminSection = function(sectionName) {
            originalSwitchAdminSection(sectionName);
            
            const titles = {
                'pms-templates': 'PMS Templates',
                'pms-schedule': 'PMS Schedule'
            };
            
            if (titles[sectionName]) {
                const titleEl = document.querySelector('#adminPageTitle') || document.querySelector('#currentSectionTitle');
                if (titleEl) titleEl.textContent = titles[sectionName];
            }
            
            // Load data when switching to PMS sections
            if (sectionName === 'pms-templates') {
                renderPMSTemplatesList();
            } else if (sectionName === 'pms-schedule') {
                generatePMSSchedules();
            }
        };

        // ========================================
        // STAFF PMS MONITORING FUNCTIONS
        // Staff side - VIEW ONLY
        // Staff hindi nagse-set ng rule. Sila ang nagre-record at nag-eexecute.
        // ========================================

        // Render Staff PMS List
        function renderStaffPMSList() {
            const list = document.getElementById('staffPMSList');
            if (!list) return;

            if (pmsSchedules.length === 0) {
                list.innerHTML = '<div class="table-row" style="text-align: center; color: #718096; padding: 2rem;">No PMS schedules available. Admin needs to create PMS templates first.</div>';
                updateStaffPMSStats();
                return;
            }

            const statusBadges = {
                overdue: '<span class="status-badge status-overdue">Overdue</span>',
                due_soon: '<span class="status-badge status-pending">Due Soon</span>',
                upcoming: '<span class="status-badge status-active">Upcoming</span>',
                completed: '<span class="status-badge status-completed">Completed</span>'
            };

            list.innerHTML = pmsSchedules.map(schedule => {
                // Get asset details para sa plate number at current meter
                const asset = assets.find(a => a.assetNum === schedule.assetNum);
                const plateNumber = asset ? asset.plateNumber : 'N/A';
                
                // Get current meter reading kung meter-based
                let currentMeter = '-';
                if (schedule.triggerType === 'meter' && asset && asset.meters) {
                    const meter = asset.meters.find(m => m.name === schedule.meterType);
                    if (meter) {
                        currentMeter = `${parseFloat(meter.value).toLocaleString()} ${schedule.meterType}`;
                    }
                }

                // Format last PMS date
                let lastPMSDate = schedule.lastCompleted || (asset ? asset.lastServiceDate : null);
                lastPMSDate = lastPMSDate ? new Date(lastPMSDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'Never';

                // Format next PMS due
                let nextPMSDue = '';
                if (schedule.triggerType === 'meter') {
                    nextPMSDue = `${schedule.dueAt.toLocaleString()} ${schedule.meterType}`;
                } else if (schedule.triggerType === 'time') {
                    nextPMSDue = new Date(schedule.dueDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
                }

                return `
                    <div class="table-row">
                        <div><strong>${schedule.assetNum}</strong></div>
                        <div>${plateNumber}</div>
                        <div>${schedule.pmsName}</div>
                        <div style="font-size: 0.9rem;">${currentMeter}</div>
                        <div>${lastPMSDate}</div>
                        <div><strong>${nextPMSDue}</strong></div>
                        <div>${statusBadges[schedule.status]}</div>
                        <div>
                            <button class="btn-small btn-primary" onclick="viewStaffPMSDetails(${schedule.id})" title="View Details">??�?/button>
                            <button class="btn-small btn-success" onclick="completeStaffPMS(${schedule.id})" title="Mark Complete">??/button>
                        </div>
                    </div>
                `;
            }).join('');

            updateStaffPMSStats();
        }

        // Update Staff PMS Statistics
        function updateStaffPMSStats() {
            const today = new Date();
            const weekFromNow = new Date();
            weekFromNow.setDate(weekFromNow.getDate() + 7);
            const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate());

            // Due this week
            const dueThisWeek = pmsSchedules.filter(s => {
                if (s.triggerType === 'time' && s.dueDate) {
                    const dueDate = new Date(s.dueDate);
                    return dueDate >= today && dueDate <= weekFromNow;
                }
                return s.status === 'due_soon';
            }).length;

            // Overdue
            const overdue = pmsSchedules.filter(s => s.status === 'overdue').length;

            // Upcoming
            const upcoming = pmsSchedules.filter(s => s.status === 'upcoming').length;

            // Completed today (would need completion tracking with timestamps)
            const completedToday = 0; // Placeholder - need to track completions with dates

            document.getElementById('staffDueThisWeek').textContent = dueThisWeek;
            document.getElementById('staffOverduePMS').textContent = overdue;
            document.getElementById('staffUpcomingPMS').textContent = upcoming;
            document.getElementById('staffCompletedToday').textContent = completedToday;
        }

        // Refresh Staff PMS List
        function refreshStaffPMSList() {
            renderStaffPMSList();
            alert('??PMS schedule refreshed!');
        }

        // View Staff PMS Details
        function viewStaffPMSDetails(id) {
            const schedule = pmsSchedules.find(s => s.id === id);
            if (!schedule) return;

            const asset = assets.find(a => a.assetNum === schedule.assetNum);
            const template = pmsTemplates.find(t => t.id === schedule.pmsTemplateId);
            
            let details = `?? PMS SCHEDULE DETAILS\n\n`;
            details += `Asset Number: ${schedule.assetNum}\n`;
            details += `Plate Number: ${asset ? asset.plateNumber : 'N/A'}\n`;
            details += `Asset Description: ${schedule.assetDescription}\n`;
            details += `PMS Name: ${schedule.pmsName}\n`;
            details += `PMS Number: ${schedule.pmsCode}\n`;
            details += `Status: ${schedule.status.toUpperCase().replace('_', ' ')}\n\n`;

            if (schedule.triggerType === 'meter') {
                details += `METER-BASED TRIGGER:\n`;
                details += `Meter Type: ${schedule.meterType}\n`;
                details += `Current Reading: ${schedule.currentValue.toLocaleString()}\n`;
                details += `Due At: ${schedule.dueAt.toLocaleString()}\n`;
                details += `Alert At: ${schedule.alertAt.toLocaleString()}\n`;
                
                if (asset && asset.meters) {
                    const meter = asset.meters.find(m => m.name === schedule.meterType);
                    if (meter) {
                        const remaining = schedule.dueAt - parseFloat(meter.value);
                        details += `Remaining: ${remaining.toLocaleString()} ${schedule.meterType}\n`;
                    }
                }
            } else if (schedule.triggerType === 'time') {
                details += `TIME-BASED TRIGGER:\n`;
                details += `Due Date: ${new Date(schedule.dueDate).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}\n`;
                details += `Alert Date: ${new Date(schedule.alertDate).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}\n`;
                
                const _dueDate = new Date(schedule.dueDate);
                const _dueMidnight = new Date(_dueDate.getFullYear(), _dueDate.getMonth(), _dueDate.getDate());
                const _nowMidnight = new Date(); const _nm = new Date(_nowMidnight.getFullYear(), _nowMidnight.getMonth(), _nowMidnight.getDate());
                const daysUntilDue = Math.round((_dueMidnight - _nm) / (1000 * 60 * 60 * 24));
                if (daysUntilDue > 0) {
                    details += `Days Until Due: ${daysUntilDue}\n`;
                } else if (daysUntilDue < 0) {
                    details += `Days Overdue: ${Math.abs(daysUntilDue)}\n`;
                } else {
                    details += `Due: TODAY\n`;
                }
            }

            if (template) {
                const totalCost = (parseFloat(template.laborCost) || 0) + (parseFloat(template.partsCost) || 0);
                details += `\nESTIMATED COST:\n`;
                details += `Labor: ₱${(parseFloat(template.laborCost) || 0).toLocaleString('en-PH', {minimumFractionDigits: 2})}\n`;
                details += `Parts: ₱${(parseFloat(template.partsCost) || 0).toLocaleString('en-PH', {minimumFractionDigits: 2})}\n`;
                details += `Total: ₱${totalCost.toLocaleString('en-PH', {minimumFractionDigits: 2})}\n`;
                
                if (template.standardServices) {
                    details += `\nSTANDARD SERVICES:\n${template.standardServices}\n`;
                }
                
                if (template.standardParts) {
                    details += `\nSTANDARD PARTS:\n${template.standardParts}`;
                }
            }

            alert(details);
        }

        // Complete Staff PMS
        function completeStaffPMS(id) {
            const schedule = pmsSchedules.find(s => s.id === id);
            if (!schedule) return;

            const asset = assets.find(a => a.assetNum === schedule.assetNum);

            if (confirm(`??Mark this PMS as complete?\n\nAsset: ${schedule.assetNum} - ${asset ? asset.plateNumber : 'N/A'}\nPMS: ${schedule.pmsName}\n\nThis will update the asset's last service date and reschedule the next PMS.`)) {
                // Update asset last service date
                if (asset) {
                    asset.lastServiceDate = new Date().toISOString().split('T')[0];
                }

                // Remove completed schedule
                pmsSchedules = pmsSchedules.filter(s => s.id !== id);

                // Regenerate schedules
                generatePMSSchedules();

                // Refresh staff list
                renderStaffPMSList();

                alert(`??PMS completed successfully!\n\nAsset: ${schedule.assetNum}\nPMS: ${schedule.pmsName}\nCompleted by: ${currentUser ? currentUser.name : 'Unknown'}\n\nThe next PMS has been scheduled automatically.`);
            }
        }

        // Staff PMS Search
        document.getElementById('staffPMSSearch')?.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const rows = document.querySelectorAll('#staffPMSList .table-row');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(searchTerm) ? 'grid' : 'none';
            });
        });

        // Domain Management
        let domains = [
            { id: 'AssetType', name: 'Asset Type', list: ['Car', 'Truck'] },
            { id: 'UOM', name: 'Unit of Measure', list: ['Each', 'Set', 'Hour', 'Piece', 'Litres', 'Gallon'] },
            { id: 'CommodityGroup', name: 'Commodity Group', list: ['Lubricants', 'Spare Parts', 'Filter', 'AutoService'] }
        ];
        window.domains = domains;

        let currentEditingDomain = null;

        // ── Item Master ──────────────────────────────────────────────
        let itemMaster = [
            {
                itemNum: 'ITM-001',
                itemName: 'Engine Oil 5W-30',
                description: 'Premium synthetic engine oil 5W-30 for diesel and gasoline engines. Suitable for trucks and buses.',
                sku: 10001,
                barcode: '1234567890123',
                qrcode: 'QR-ENG-OIL-001',
                commodityGroup: 'Lubricants',
                uom: 'Litres',
                cost: 450.00,
                itemType: 'Material'
            },
            {
                itemNum: 'ITM-002',
                itemName: 'Brake Pads Set',
                description: 'Heavy duty brake pads for trucks and buses. High performance ceramic compound.',
                sku: 10002,
                barcode: '2345678901234',
                qrcode: 'QR-BRK-PAD-002',
                commodityGroup: 'Spare Parts',
                uom: 'Set',
                cost: 1200.00,
                itemType: 'Material'
            },
            {
                itemNum: 'ITM-003',
                itemName: 'Air Filter',
                description: 'Standard air filter for diesel engines. Compatible with Isuzu and Hino vehicles.',
                sku: 10003,
                barcode: '3456789012345',
                qrcode: 'QR-FLT-AIR-003',
                commodityGroup: 'Filter',
                uom: 'Each',
                cost: 350.00,
                itemType: 'Material'
            },
            {
                itemNum: 'ITM-004',
                itemName: 'Radial Tire 10R22.5',
                description: 'Heavy duty radial tire 10R22.5 for trucks. All-weather tread pattern.',
                sku: 10004,
                barcode: '4567890123456',
                qrcode: 'QR-TIR-RAD-004',
                commodityGroup: 'Spare Parts',
                uom: 'Each',
                cost: 8500.00,
                itemType: 'Material'
            },
            {
                itemNum: 'ITM-005',
                itemName: 'Oil Change Service',
                description: 'Labor charge for engine oil change service.',
                sku: 10005,
                barcode: '5678901234567',
                qrcode: 'QR-SVC-OIL-005',
                commodityGroup: 'AutoService',
                uom: 'Hour',
                cost: 500.00,
                itemType: 'Service'
            }
        ];
        let currentEditingItemMaster = null;
        window.itemMaster = itemMaster;

        function renderItemMasterList() {
            const list = document.getElementById('itemMasterList');
            if (!list) return;
            const search = (document.getElementById('itemMasterSearch')?.value || '').toLowerCase();
            const filtered = itemMaster.filter(i =>
                i.itemNum.toLowerCase().includes(search) ||
                i.itemName.toLowerCase().includes(search) ||
                (i.commodityGroup || '').toLowerCase().includes(search)
            );
            if (filtered.length === 0) {
                list.innerHTML = '<div class="table-row" style="text-align:center;color:#718096;padding:2rem;">No items found. Click "Add Item" to create one.</div>';
                return;
            }
            const typeBadge = t => t === 'Material'
                ? '<span style="background:#bee3f8;color:#2c5282;padding:0.2rem 0.6rem;border-radius:12px;font-size:0.8rem;font-weight:600;">Material</span>'
                : '<span style="background:#e9d8fd;color:#553c9a;padding:0.2rem 0.6rem;border-radius:12px;font-size:0.8rem;font-weight:600;">Service</span>';
            list.innerHTML = filtered.map(i => `
                <div class="table-row" style="grid-template-columns: 1fr 1fr 1.5fr 1fr 1fr 1fr 1fr 100px;">
                    <div><strong>${i.itemNum}</strong></div>
                    <div>${i.itemName}</div>
                    <div style="font-size:0.85rem;color:#4a5568;">${i.description || '-'}</div>
                    <div>${i.commodityGroup}</div>
                    <div>${i.uom}</div>
                    <div>${typeBadge(i.itemType)}</div>
                    <div>₱${(i.cost || 0).toLocaleString('en-PH', {minimumFractionDigits:2})}</div>
                    <div style="display:flex;gap:0.3rem;flex-wrap:nowrap;">
                        <button class="btn-small btn-primary" onclick="viewItemMaster('${i.itemNum}')" title="View">👁️</button>
                        <button class="btn-small btn-secondary" onclick="editItemMaster('${i.itemNum}')" title="Edit">✏️</button>
                        <button class="btn-small btn-danger" onclick="deleteItemMaster('${i.itemNum}')" title="Delete">🗑️</button>
                    </div>
                </div>
            `).join('');
        }

        function viewItemMaster(itemNum) {
            const item = itemMaster.find(i => i.itemNum === itemNum);
            if (!item) return;

            const typeBg   = item.itemType === 'Material' ? '#bee3f8' : '#e9d8fd';
            const typeClr  = item.itemType === 'Material' ? '#2c5282' : '#553c9a';

            document.getElementById('imIcon').textContent    = item.itemType === 'Service' ? '🔧' : '📦';
            document.getElementById('imItemName').textContent = item.itemName;
            document.getElementById('imItemNum').textContent  = item.itemNum + (item.sku ? '  ·  SKU: ' + item.sku : '');
            document.getElementById('imTypeBadge').innerHTML  =
                `<span style="background:${typeBg};color:${typeClr};padding:0.3rem 0.85rem;border-radius:20px;font-size:0.78rem;font-weight:700;">${item.itemType}</span>`;
            document.getElementById('imGroupBadge').textContent = item.commodityGroup || '-';

            document.getElementById('imCost').textContent = '₱' + (item.cost || 0).toLocaleString('en-PH', { minimumFractionDigits: 2 });
            document.getElementById('imUOM').textContent  = item.uom || '-';
            document.getElementById('imSKU').textContent  = item.sku || '-';

            document.getElementById('imDesc').textContent = item.description || 'No description available.';

            const infoItems = [
                { label: 'Item Number',      value: item.itemNum },
                { label: 'Commodity Group',  value: item.commodityGroup || '-' },
                { label: 'Unit of Measure',  value: item.uom || '-' },
                { label: 'Item Type',        value: item.itemType || '-' },
                { label: 'SKU',              value: item.sku || '-' },
                { label: 'Unit Cost',        value: '₱' + (item.cost || 0).toLocaleString('en-PH', { minimumFractionDigits: 2 }) },
            ];
            document.getElementById('imInfoGrid').innerHTML = infoItems.map(i => `
                <div style="background:#f7fafc;border-radius:10px;padding:0.85rem 1rem;">
                    <div style="font-size:0.7rem;color:#718096;font-weight:700;text-transform:uppercase;letter-spacing:0.4px;margin-bottom:0.3rem;">${i.label}</div>
                    <div style="font-weight:700;color:#1a202c;font-size:0.92rem;">${i.value}</div>
                </div>
            `).join('');

            document.getElementById('imBarcode').textContent = item.barcode || '-';
            document.getElementById('imQR').textContent      = item.qrcode  || '-';

            document.getElementById('itemMasterDetailsModal').classList.add('active');
        }

        function openAddItemMasterModal() {
            currentEditingItemMaster = null;
            document.getElementById('itemMasterModalTitle').textContent = 'Add Item';
            document.getElementById('addItemMasterForm').reset();
            populateItemMasterDropdowns();

            // Auto-generate next item number
            const nums = itemMaster
                .map(i => parseInt((i.itemNum || '').replace(/\D/g, ''), 10))
                .filter(n => !isNaN(n));
            const next = nums.length ? Math.max(...nums) + 1 : 1;
            const form = document.getElementById('addItemMasterForm');
            form.elements.itemNum.value = 'ITM-' + String(next).padStart(3, '0');

            // Auto-generate next SKU number
            const skuNums = itemMaster
                .map(i => parseInt(i.sku, 10))
                .filter(n => !isNaN(n));
            const nextSku = skuNums.length ? Math.max(...skuNums) + 1 : 10001;
            form.elements.sku.value = nextSku;

            // Reset barcode/QR row visibility
            document.getElementById('imBarcodeQRRow').style.display = '';

            document.getElementById('addItemMasterModal').classList.add('active');
        }

        function populateItemMasterUOM() {
            const uomDomain = domains.find(d => d.id === 'UOM');
            const list = uomDomain ? uomDomain.list : ['Each', 'Set', 'Hour', 'Piece', 'Litres', 'Gallon'];
            const sel = document.getElementById('itemMasterUOM');
            sel.innerHTML = '<option value="">Select UOM</option>' + list.map(v => `<option value="${v}">${v}</option>`).join('');
        }

        function editItemMaster(itemNum) {
            const item = itemMaster.find(i => i.itemNum === itemNum);
            if (!item) return;
            currentEditingItemMaster = item;
            document.getElementById('itemMasterModalTitle').textContent = 'Edit Item';
            populateItemMasterDropdowns();
            const form = document.getElementById('addItemMasterForm');
            form.elements.itemNum.value = item.itemNum;
            document.getElementById('itemMasterItemNum').readOnly = true;
            form.elements.itemName.value = item.itemName;
            form.elements.description.value = item.description || '';
            form.elements.sku.value = item.sku || '';
            form.elements.barcode.value = item.barcode || '';
            form.elements.qrcode.value = item.qrcode || '';
            setTimeout(() => {
                form.elements.commodityGroup.value = item.commodityGroup || '';
                form.elements.uom.value = item.uom || '';
                form.elements.itemType.value = item.itemType || '';
                const isService = (item.commodityGroup || '').toLowerCase() === 'autoservice' || item.itemType === 'Service';
                document.getElementById('imBarcodeQRRow').style.display = isService ? 'none' : '';
            }, 50);
            form.elements.cost.value = item.cost || '';
            document.getElementById('addItemMasterModal').classList.add('active');
        }

        function deleteItemMaster(itemNum) {
            const item = itemMaster.find(i => i.itemNum === itemNum);
            if (!item) return;
            if (confirm(`Delete ${item.itemName}? This cannot be undone.`)) {
                const docId = window._fbItemMaster?.find(i => i.num === itemNum)?._id;
                if (docId) {
                    db.collection('item_master').doc(docId).delete()
                        .then(() => showToast('Item deleted.', 'success'))
                        .catch(err => showToast('Delete failed: ' + err.message, 'error'));
                } else {
                    showToast('Item not found in database.', 'error');
                }
            }
        }

        document.getElementById('addItemMasterForm')?.addEventListener('submit', e => {
            e.preventDefault();
            const form = e.target;
            const itemNum = form.elements.itemNum.value.trim();
            const data = {
                num:            itemNum,
                name:           form.elements.itemName.value.trim(),
                desc:           form.elements.description.value.trim(),
                sku:            form.elements.sku.value.trim(),
                barcode:        form.elements.barcode.value.trim(),
                qr:             form.elements.qrcode.value.trim(),
                group:          form.elements.commodityGroup.value,
                uom:            form.elements.uom.value,
                cost:           parseFloat(form.elements.cost.value) || 0,
                type:           form.elements.itemType.value,
            };

            if (currentEditingItemMaster) {
                // Edit — find Firestore doc id
                const docId = window._fbItemMaster?.find(i => i.num === itemNum)?._id;
                if (!docId) { showToast('Item not found in database.', 'error'); return; }
                db.collection('item_master').doc(docId).update(data)
                    .then(() => { showToast('Item updated successfully!', 'success'); closeModal('addItemMasterModal'); })
                    .catch(err => showToast('Update failed: ' + err.message, 'error'));
            } else {
                // Add — check duplicate then create
                const isDuplicate = itemMaster.some(i => i.itemNum === itemNum);
                if (isDuplicate) { alert('Item Number already exists.'); return; }
                data.createdAt = firebase.firestore.FieldValue.serverTimestamp();
                db.collection('item_master').add(data)
                    .then(() => { showToast('Item added successfully!', 'success'); closeModal('addItemMasterModal'); })
                    .catch(err => showToast('Save failed: ' + err.message, 'error'));
            }
        });
        // ─────────────────────────────────────────────────────────────

        function openItemMasterScanModal() {
            document.getElementById('itemMasterScanInput').value = '';
            document.getElementById('itemMasterScanModal').classList.add('active');
        }

        function searchItemMasterByScan() {
            const raw = document.getElementById('itemMasterScanInput').value.trim();
            if (!raw) { alert('Please enter a barcode or QR code to search.'); return; }
            const query = raw.toLowerCase();

            // Exact match on barcode or qrcode first, then fallback to itemNum / name
            const found = itemMaster.find(i =>
                (i.barcode && i.barcode.toLowerCase() === query) ||
                (i.qrcode  && i.qrcode.toLowerCase()  === query)
            ) || itemMaster.find(i =>
                (i.itemNum && i.itemNum.toLowerCase() === query) ||
                (i.itemName && i.itemName.toLowerCase().includes(query))
            );

            closeModal('itemMasterScanModal');

            if (!found) {
                alert(`No item found for: "${raw}"`);
                return;
            }

            // Clear search, set to found item number, re-render
            const searchBar = document.getElementById('itemMasterSearch');
            if (searchBar) {
                searchBar.value = found.itemNum;
                renderItemMasterList();
            }

            // Highlight the matching row
            setTimeout(() => {
                const rows = document.querySelectorAll('#itemMasterList .table-row');
                rows.forEach(row => {
                    if (row.textContent.includes(found.itemNum)) {
                        row.style.background = '#ebf8ff';
                        row.style.transition = 'background 1.5s';
                        row.scrollIntoView({ behavior: 'smooth', block: 'center' });
                        setTimeout(() => { row.style.background = ''; }, 2500);
                    }
                });
            }, 100);
        }

        function onItemMasterCommodityGroupChange(select) {
            const isService = select.value.toLowerCase() === 'autoservice';
            const itemTypeEl = document.getElementById('itemMasterItemType');
            const barcodeRow = document.getElementById('imBarcodeQRRow');

            if (isService) {
                itemTypeEl.value = 'Service';
                barcodeRow.style.display = 'none';
                document.getElementById('itemMasterBarcode').value = '';
                document.getElementById('itemMasterQRCode').value = '';
            } else {
                itemTypeEl.value = '';
                barcodeRow.style.display = '';
            }
        }

        function generateItemMasterBarcode() {
            const itemNumEl = document.querySelector('#addItemMasterForm [name="itemNum"]');
            const barcodeEl = document.getElementById('itemMasterBarcode');
            const base = itemNumEl?.value.trim() || 'ITM';
            barcodeEl.value = 'BC-' + base.replace(/[^a-zA-Z0-9]/g, '') + '-' + Date.now().toString().slice(-6);
        }

        function generateItemMasterQRCode() {
            const itemNumEl = document.querySelector('#addItemMasterForm [name="itemNum"]');
            const qrEl = document.getElementById('itemMasterQRCode');
            const base = itemNumEl?.value.trim() || 'ITM';
            qrEl.value = 'QR-' + base.replace(/[^a-zA-Z0-9]/g, '') + '-' + Date.now().toString().slice(-6);
        }

        function renderDomainsList() {
            const list = document.getElementById('domainsList');
            if (!list) return;

            const search = (document.getElementById('domainSearch')?.value || '').toLowerCase();
            const filtered = domains.filter(d =>
                d.id.toLowerCase().includes(search) ||
                d.name.toLowerCase().includes(search) ||
                d.list.join(',').toLowerCase().includes(search)
            );

            if (filtered.length === 0) {
                list.innerHTML = '<div style="padding: 2rem; text-align: center; color: #718096;">No domains found.</div>';
                return;
            }

            list.innerHTML = filtered.map((d, i) => `
                <div class="table-row" style="grid-template-columns:40px 1.5fr 3fr 120px;align-items:center;">
                    <div style="color:#a0aec0;font-size:0.85rem;">${i + 1}</div>
                    <div style="font-weight:600;color:#1a202c;">${d.name}</div>
                    <div style="display:flex;flex-wrap:wrap;gap:4px;align-items:center;">
                        ${d.list.map(v => `<span style="background:#edf2f7;color:#4a5568;padding:3px 10px;border-radius:20px;font-size:0.8rem;font-weight:500;white-space:nowrap;">${v}</span>`).join('')}
                        <span style="color:#a0aec0;font-size:0.78rem;margin-left:4px;">(${d.list.length})</span>
                    </div>
                    <div style="display:flex;gap:0.4rem;">
                        <button class="btn-small btn-primary" onclick="editDomain('${d.id}')">✏️ Edit</button>
                        <button class="btn-small btn-danger" onclick="deleteDomain('${d.id}')">🗑️</button>
                    </div>
                </div>
            `).join('');
        }

        function openAddDomainModal() {
            currentEditingDomain = null;
            document.getElementById('addDomainForm').reset();
            document.getElementById('domainModalTitle').textContent = 'Add Domain';
            document.getElementById('addDomainModal').classList.add('active');
        }

        function editDomain(domainId) {
            const domain = domains.find(d => d.id === domainId);
            if (!domain) return;
            currentEditingDomain = domain;

            const form = document.getElementById('addDomainForm');
            form.elements.domainName.value = domain.name;
            form.elements.domainList.value = domain.list.join(', ');

            document.getElementById('domainModalTitle').textContent = 'Edit Domain';
            document.getElementById('addDomainModal').classList.add('active');
        }

        function deleteDomain(domainId) {
            const domain = domains.find(d => d.id === domainId);
            if (!domain) return;
            if (confirm('Delete domain "' + domain.name + '"?\n\nThis cannot be undone.')) {
                domains = domains.filter(d => d.id !== domainId);
                renderDomainsList();
            }
        }

        document.getElementById('addDomainForm')?.addEventListener('submit', function(e) {
            e.preventDefault();
            const form = e.target;
            const domainName = form.elements.domainName.value.trim();
            const list = form.elements.domainList.value
                .split(',').map(function(v) { return v.trim(); }).filter(function(v) { return v.length > 0; });

            if (list.length === 0) {
                alert('Please enter at least one value in the domain list.');
                return;
            }

            if (currentEditingDomain) {
                const domain = domains.find(d => d.id === currentEditingDomain.id);
                if (domain) { domain.name = domainName; domain.list = list; }
            } else {
                const autoId = domainName.replace(/\s+/g, '') + '_' + Date.now();
                domains.push({ id: autoId, name: domainName, list: list });
            }

            renderDomainsList();
            closeModal('addDomainModal');
        });

        document.getElementById('domainSearch')?.addEventListener('input', renderDomainsList);

        document.getElementById('itemMasterSearch')?.addEventListener('input', renderItemMasterList);



        // ─── SMART REPORTS (RAG) ────────────────────────────────────────────────

        function clearSmartChat() {
            const messages = document.getElementById('srChatMessages');
            if (!messages) return;
            messages.innerHTML = `
                <div class="sr-welcome-bubble">
                    <div class="sr-avatar-ai">🤖</div>
                    <div class="sr-bubble-ai">
                        <div style="font-weight:700;margin-bottom:0.4rem;font-size:0.95rem;">Hello! I'm your Smart Reports assistant. 👋</div>
                        <div style="color:#4a5568;font-size:0.88rem;line-height:1.6;margin-bottom:1rem;">Ask me anything about your fleet — assets, inventory, maintenance costs, and more. Try one of these to get started:</div>
                        <div class="sr-welcome-chips">
                            <button class="sr-suggest-chip" onclick="setAndRunQuery('Which assets are frequently under maintenance?')">🔧 Frequently maintained assets</button>
                            <button class="sr-suggest-chip" onclick="setAndRunQuery('What items are low in stock?')">📦 Low stock items</button>
                            <button class="sr-suggest-chip" onclick="setAndRunQuery('Total repair cost this month')">💰 Repair cost this month</button>
                            <button class="sr-suggest-chip" onclick="setAndRunQuery('Assets with PMS overdue')">⚠️ PMS overdue assets</button>
                            <button class="sr-suggest-chip" onclick="setAndRunQuery('Which assets are under maintenance?')">🔵 Under maintenance</button>
                            <button class="sr-suggest-chip" onclick="setAndRunQuery('What are the fast moving inventory items?')">📈 Fast moving inventory</button>
                        </div>
                    </div>
                </div>`;
        }

        function setAndRunQuery(text) {
            const input = document.getElementById('smartQueryInput');
            if (input) { input.value = text; input.style.height = 'auto'; }
            runSmartQuery();
        }

        function runSmartQuery() {
            const input = document.getElementById('smartQueryInput');
            const query = input ? input.value.trim() : '';
            if (!query) return;

            // Hide welcome screen on first query
            const welcome = document.querySelector('.sr-welcome');
            if (welcome) welcome.style.display = 'none';

            // Append user bubble
            appendChatBubble('user', query);

            // Clear input
            input.value = '';
            input.style.height = 'auto';

            // Show typing indicator
            const typingId = appendTypingIndicator();

            // Simulate slight delay for realism
            setTimeout(() => {
                removeTypingIndicator(typingId);
                const result = processSmartQuery(query);
                appendChatBubble('ai', null, result);
                scrollChatToBottom();
            }, 600);
        }

        function appendChatBubble(role, text, result) {
            const messages = document.getElementById('srChatMessages');
            const wrap = document.createElement('div');
            wrap.className = role === 'user' ? 'sr-msg-row sr-msg-user' : 'sr-msg-row sr-msg-ai';

            if (role === 'user') {
                wrap.innerHTML = `
                    <div class="sr-bubble-user">${escapeHtml(text)}</div>
                    <div class="sr-avatar-user">👤</div>`;
            } else {
                wrap.innerHTML = `
                    <div class="sr-avatar-ai">🤖</div>
                    <div class="sr-bubble-ai">${buildResultHtml(result)}</div>`;
            }
            messages.appendChild(wrap);
            scrollChatToBottom();
        }

        function appendTypingIndicator() {
            const messages = document.getElementById('srChatMessages');
            const id = 'typing_' + Date.now();
            const wrap = document.createElement('div');
            wrap.className = 'sr-msg-row sr-msg-ai';
            wrap.id = id;
            wrap.innerHTML = `
                <div class="sr-avatar-ai">🤖</div>
                <div class="sr-bubble-ai sr-typing">
                    <span></span><span></span><span></span>
                </div>`;
            messages.appendChild(wrap);
            scrollChatToBottom();
            return id;
        }

        function removeTypingIndicator(id) {
            const el = document.getElementById(id);
            if (el) el.remove();
        }

        function scrollChatToBottom() {
            const messages = document.getElementById('srChatMessages');
            if (messages) messages.scrollTop = messages.scrollHeight;
        }

        function escapeHtml(str) {
            return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        }

        function buildResultHtml(result) {
            const colorMap = {
                danger:  { border: '#e53e3e', badge: '#fed7d7', badgeText: '#742a2a', header: '#e53e3e' },
                warning: { border: '#d69e2e', badge: '#fefcbf', badgeText: '#744210', header: '#d69e2e' },
                success: { border: '#38a169', badge: '#c6f6d5', badgeText: '#22543d', header: '#38a169' },
                green:   { border: '#38a169', badge: '#c6f6d5', badgeText: '#22543d', header: '#38a169' },
                blue:    { border: '#3182ce', badge: '#bee3f8', badgeText: '#1a365d', header: '#3182ce' },
                orange:  { border: '#ed8936', badge: '#feebc8', badgeText: '#7c2d12', header: '#ed8936' },
                purple:  { border: '#805ad5', badge: '#e9d8fd', badgeText: '#44337a', header: '#805ad5' },
                info:    { border: '#718096', badge: '#e2e8f0', badgeText: '#2d3748', header: '#718096' }
            };
            const c = colorMap[result.type] || colorMap.info;

            // Store for export
            window._lastSmartResult = result;

            const tableHtml = result.rows.length > 0 ? `
                <div style="border-radius:10px;overflow:hidden;border:1px solid #e2e8f0;margin-top:1rem;">
                    <table style="width:100%;border-collapse:collapse;background:white;">
                        <thead>
                            <tr style="background:${c.header};">
                                <th style="padding:0.6rem 0.9rem;text-align:left;color:white;font-size:0.75rem;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;width:36px;">#</th>
                                <th style="padding:0.6rem 0.9rem;text-align:left;color:white;font-size:0.75rem;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;">Item</th>
                                <th style="padding:0.6rem 0.9rem;text-align:right;color:white;font-size:0.75rem;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;">Value</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${result.rows.map((r, i) => `
                                <tr style="background:${i % 2 === 0 ? '#f9fafb' : 'white'};border-bottom:1px solid #e2e8f0;">
                                    <td style="padding:0.65rem 0.9rem;color:#a0aec0;font-size:0.8rem;font-weight:600;">${i + 1}</td>
                                    <td style="padding:0.65rem 0.9rem;font-weight:600;color:#1a202c;font-size:0.88rem;">${r.label}</td>
                                    <td style="padding:0.65rem 0.9rem;text-align:right;">
                                        <span style="background:${c.badge};color:${c.badgeText};padding:0.25rem 0.75rem;border-radius:20px;font-size:0.78rem;font-weight:700;white-space:nowrap;">${r.value}</span>
                                    </td>
                                </tr>`).join('')}
                        </tbody>
                    </table>
                </div>
                <div style="margin-top:0.5rem;font-size:0.75rem;color:#a0aec0;text-align:right;">${result.rows.length} result(s)</div>` : '';

            const exportBtns = result.rows.length > 0 ? `
                <div style="display:flex;gap:0.5rem;margin-top:1rem;padding-top:0.85rem;border-top:1px solid #e2e8f0;">
                    <button onclick="exportSmartReportPDF()" style="background:#e53e3e;color:white;padding:0.45rem 1rem;border:none;border-radius:8px;font-size:0.8rem;font-weight:600;cursor:pointer;display:flex;align-items:center;gap:0.35rem;">📄 PDF</button>
                    <button onclick="exportSmartReportExcel()" style="background:#38a169;color:white;padding:0.45rem 1rem;border:none;border-radius:8px;font-size:0.8rem;font-weight:600;cursor:pointer;display:flex;align-items:center;gap:0.35rem;">📊 Excel</button>
                </div>` : '';

            // Follow-up suggestion chips (ChatGPT style)
            const followUpChips = `
                <div style="margin-top:1rem;padding-top:0.85rem;border-top:1px solid #e2e8f0;">
                    <div style="font-size:0.75rem;color:#a0aec0;font-weight:600;margin-bottom:0.5rem;text-transform:uppercase;letter-spacing:0.5px;">Try asking:</div>
                    <div style="display:flex;flex-wrap:wrap;gap:0.4rem;">
                        <button class="sr-suggest-chip" onclick="setAndRunQuery('What items are low in stock?')">📦 Low stock items</button>
                        <button class="sr-suggest-chip" onclick="setAndRunQuery('Assets with PMS overdue')">⚠️ PMS overdue</button>
                        <button class="sr-suggest-chip" onclick="setAndRunQuery('Total repair cost this month')">💰 Monthly cost</button>
                        <button class="sr-suggest-chip" onclick="setAndRunQuery('Which assets are under maintenance?')">🔵 Under maintenance</button>
                        <button class="sr-suggest-chip" onclick="setAndRunQuery('Which assets are frequently under maintenance?')">🔧 Most maintained</button>
                    </div>
                </div>`;

            return `
                <div style="display:flex;align-items:center;gap:0.6rem;margin-bottom:0.5rem;">
                    <span style="font-size:1.3rem;">${result.icon}</span>
                    <div>
                        <div style="font-size:0.95rem;font-weight:800;color:#1a202c;">${result.title}</div>
                        <div style="font-size:0.83rem;color:#718096;margin-top:0.1rem;">${result.body}</div>
                    </div>
                </div>
                ${tableHtml}
                ${exportBtns}
                ${followUpChips}`;
        }

        function processSmartQuery(query) {
            const q = query.toLowerCase();
            const today = new Date();
            today.setHours(0, 0, 0, 0);

            // ── Intent Detection System ────────────────────────────────────────
            const intents = [
                {
                    name: 'under_maintenance',
                    patterns: [
                        /\b(under|being|currently|in|for)\b.*(maintenance|repair|service|servic)/,
                        /\b(maintenance|repair|servic)\b.*(now|current|ongoing|active|status)/,
                        /which.*(being|under|in).*(service|repair|maintenance)/,
                        /\b(fix|fixing|repaired?|shop)\b/
                    ]
                },
                {
                    name: 'pms_overdue',
                    patterns: [
                        /\b(overdue|over due|past due|missed|late|behind|expired)\b/,
                        /pms.*(overdue|missed|late|past|behind)/,
                        /(overdue|missed|late).*(pms|maintenance|service|schedule)/,
                        /\b(haven.t|has not|not yet|no).*(service|maintain|pms)\b/
                    ]
                },
                {
                    name: 'pms_due_soon',
                    patterns: [
                        /\b(due soon|coming up|upcoming|approaching|near|soon|next|schedule)\b.*(pms|maintenance|service)/,
                        /\b(pms|maintenance|service)\b.*(due soon|coming|upcoming|soon|next|schedule|when)/,
                        /when.*(next|due|schedule).*(service|pms|maintenance)/
                    ]
                },
                {
                    name: 'low_stock',
                    patterns: [
                        /\b(low stock|low in stock|low inventory|reorder|stock alert|running low|need.*(restock|reorder))\b/,
                        /\b(stock|inventory)\b.*(low|critical|alert|warning|minimum)/,
                        /what.*(need|should).*(order|restock|reorder)/,
                        /\b(out of stock|stockout|no stock)\b/
                    ]
                },
                {
                    name: 'monthly_cost',
                    patterns: [
                        /\b(monthly|this month|month|repair cost|total cost|expense|spend|spent)\b/,
                        /how much.*(cost|spend|spent|paid|expense)/,
                        /\b(maintenance|repair|service)\b.*(cost|expense|spend|budget)/
                    ]
                },
                {
                    name: 'frequently_maintained',
                    patterns: [
                        /\b(frequent|most maintained|most repaired|frequently|often|always|repeatedly)\b/,
                        /which.*(most|frequent|often|always).*(maintain|repair|service)/,
                        /\b(problem|problematic|trouble|issue).*(asset|vehicle|unit)/
                    ]
                },
                {
                    name: 'fast_moving',
                    patterns: [
                        /\b(fast moving|fast-moving|most used|frequently used|popular|high demand)\b/,
                        /which.*(item|part|material).*(most|frequent|often|popular)/,
                        /\b(top|best).*(selling|used|consumed)\b/
                    ]
                },
                {
                    name: 'asset_list',
                    patterns: [
                        /\b(list|show|display|view|what|how many|count|all)\b.*\b(asset|vehicle|truck|car|fleet|unit)\b/,
                        /\b(asset|vehicle|truck|car|fleet|unit)\b.*\b(list|all|do (i|we) have|owned)\b/,
                        /how many.*(asset|vehicle|truck|car)/
                    ]
                },
                {
                    name: 'inventory_status',
                    patterns: [
                        /\b(inventory|stock)\b.*(status|level|summary|overview)/,
                        /what.*(inventory|stock|part|material).*(have|available)/,
                        /\b(show|list|display).*(inventory|stock|part)\b/
                    ]
                },
                {
                    name: 'cost_breakdown',
                    patterns: [
                        /\b(cost breakdown|breakdown|detail|itemize|break down)\b/,
                        /\b(where|what).*(money|cost|expense|budget).*(go|went|spent)/
                    ]
                },
                {
                    name: 'asset_performance',
                    patterns: [
                        /\b(performance|efficiency|reliability|uptime|downtime)\b/,
                        /which.*(best|worst|good|bad|reliable|unreliable)/,
                        /\b(compare|comparison).*(asset|vehicle|fleet)/
                    ]
                }
            ];

            function detectIntent(text) {
                for (let i = 0; i < intents.length; i++) {
                    for (let j = 0; j < intents[i].patterns.length; j++) {
                        if (intents[i].patterns[j].test(text)) return intents[i].name;
                    }
                }
                return null;
            }

            const intent = detectIntent(q);

            // ── Intent Handlers ─────────────────────────────────────────────────

            if (intent === 'under_maintenance') {
                const list = assets.filter(a => a.status === 'maintenance');
                if (list.length === 0) return { type: 'info', title: 'Assets Under Maintenance', icon: '🔵', body: 'No assets are currently under maintenance.', rows: [] };
                return {
                    type: 'blue',
                    title: 'Assets Currently Under Maintenance',
                    icon: '🔵',
                    body: `${list.length} asset(s) are currently under maintenance.`,
                    rows: list.map(a => ({ label: `${a.assetNum} – ${a.assetDescription}`, value: a.owner }))
                };
            }

            if (intent === 'pms_overdue') {
                const list = assets.filter(a => {
                    if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                    const due = new Date(a.nextPMSDue);
                    due.setHours(0, 0, 0, 0);
                    return due < today;
                });
                if (list.length === 0) return { type: 'success', title: 'PMS Overdue Assets', icon: '✅', body: 'Great news! No assets are overdue for PMS.', rows: [] };
                return {
                    type: 'danger',
                    title: 'Assets with PMS Overdue',
                    icon: '⚠️',
                    body: `${list.length} asset(s) have overdue PMS schedules. Immediate attention required.`,
                    rows: list.map(a => {
                        const due = new Date(a.nextPMSDue);
                        const diff = Math.ceil((today - due) / 86400000);
                        return { label: `${a.assetNum} – ${a.assetDescription}`, value: `Overdue by ${diff} day(s)` };
                    })
                };
            }

            if (intent === 'pms_due_soon') {
                const list = assets.filter(a => {
                    if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                    const due = new Date(a.nextPMSDue);
                    due.setHours(0, 0, 0, 0);
                    const diff = Math.ceil((due - today) / 86400000);
                    return diff >= 0 && diff <= 14;
                });
                if (list.length === 0) return { type: 'success', title: 'PMS Due Soon', icon: '✅', body: 'No assets have PMS due in the next 14 days.', rows: [] };
                return {
                    type: 'warning',
                    title: 'Assets with PMS Due Soon',
                    icon: '📅',
                    body: `${list.length} asset(s) have PMS due within the next 14 days.`,
                    rows: list.map(a => {
                        const due = new Date(a.nextPMSDue);
                        const diff = Math.ceil((due - today) / 86400000);
                        return { label: `${a.assetNum} – ${a.assetDescription}`, value: diff === 0 ? 'Due today!' : `Due in ${diff} day(s)` };
                    })
                };
            }

            if (intent === 'low_stock') {
                const list = inventory.filter(i => i.status === 'low_stock' || i.status === 'out_of_stock' || i.stock <= (i.minLevel || i.reorderLevel || 0));
                if (list.length === 0) return { type: 'success', title: 'Low Stock Items', icon: '✅', body: 'All inventory items are sufficiently stocked.', rows: [] };
                return {
                    type: 'warning',
                    title: 'Low Stock Inventory Items',
                    icon: '📦',
                    body: `${list.length} item(s) are at or below minimum stock level.`,
                    rows: list.map(i => ({ label: `${i.itemNum} – ${i.itemName}`, value: `${i.stock} ${i.unit} (min: ${i.minLevel})` }))
                };
            }

            if (intent === 'monthly_cost') {
                const now = new Date();
                const thisMonth = now.getMonth();
                const thisYear = now.getFullYear();
                const monthTxns = serviceTransactions.filter(s => {
                    const d = new Date(s.dateServiced);
                    return d.getMonth() === thisMonth && d.getFullYear() === thisYear;
                });
                const total = monthTxns.reduce((sum, s) => sum + (s.totalCost || 0), 0);
                const monthName = now.toLocaleString('en-US', { month: 'long' });
                return {
                    type: 'green',
                    title: `Total Repair Cost – ${monthName} ${thisYear}`,
                    icon: '💰',
                    body: `Total maintenance cost this month: ₱${total.toLocaleString()}`,
                    rows: monthTxns.map(s => ({ label: `${s.serviceId} – ${s.assetDescription}`, value: `₱${(s.totalCost || 0).toLocaleString()}` }))
                };
            }

            if (intent === 'frequently_maintained') {
                const counts = assets.map(a => ({
                    asset: a,
                    count: (a.maintenanceHistory || []).length
                })).sort((a, b) => b.count - a.count);
                return {
                    type: 'orange',
                    title: 'Most Frequently Maintained Assets',
                    icon: '🔧',
                    body: `Ranked by number of maintenance records on file.`,
                    rows: counts.map((c, i) => ({ label: `${i + 1}. ${c.asset.assetNum} – ${c.asset.assetDescription}`, value: `${c.count} record(s)` }))
                };
            }

            if (intent === 'fast_moving') {
                const usageMap = {};
                serviceTransactions.forEach(s => {
                    (s.spareParts || []).forEach(p => {
                        usageMap[p.name] = (usageMap[p.name] || 0) + (p.quantity || 1);
                    });
                });
                const sorted = Object.entries(usageMap).sort((a, b) => b[1] - a[1]);
                if (sorted.length === 0) return { type: 'info', title: 'Fast Moving Inventory', icon: '📈', body: 'No issuance data available yet.', rows: [] };
                return {
                    type: 'purple',
                    title: 'Fast Moving Inventory Items',
                    icon: '📈',
                    body: 'Items ranked by total quantity used in service transactions.',
                    rows: sorted.map(([name, qty]) => ({ label: name, value: `${qty} units used` }))
                };
            }

            if (intent === 'asset_list') {
                if (assets.length === 0) return { type: 'info', title: 'All Assets', icon: '🚗', body: 'No assets registered in the system.', rows: [] };
                return {
                    type: 'blue',
                    title: 'All Registered Assets',
                    icon: '🚗',
                    body: `Total of ${assets.length} asset(s) in the fleet.`,
                    rows: assets.map(a => ({ label: `${a.assetNum} – ${a.assetDescription}`, value: a.status || 'active' }))
                };
            }

            if (intent === 'inventory_status') {
                if (inventory.length === 0) return { type: 'info', title: 'Inventory Status', icon: '📦', body: 'No inventory items in the system.', rows: [] };
                const totalValue = inventory.reduce((sum, i) => sum + (i.stock * (i.price || 0)), 0);
                return {
                    type: 'blue',
                    title: 'Inventory Status Overview',
                    icon: '📦',
                    body: `${inventory.length} item(s) in inventory. Total value: ₱${totalValue.toLocaleString()}`,
                    rows: inventory.map(i => ({ label: `${i.itemNum} – ${i.itemName}`, value: `${i.stock} ${i.unit}` }))
                };
            }

            if (intent === 'cost_breakdown') {
                const now = new Date();
                const thisMonth = now.getMonth();
                const thisYear = now.getFullYear();
                const monthTxns = serviceTransactions.filter(s => {
                    const d = new Date(s.dateServiced);
                    return d.getMonth() === thisMonth && d.getFullYear() === thisYear;
                });
                const byAsset = {};
                monthTxns.forEach(s => {
                    const key = s.assetNum || 'Unknown';
                    byAsset[key] = (byAsset[key] || 0) + (s.totalCost || 0);
                });
                const sorted = Object.entries(byAsset).sort((a, b) => b[1] - a[1]);
                const monthName = now.toLocaleString('en-US', { month: 'long' });
                return {
                    type: 'green',
                    title: `Cost Breakdown by Asset – ${monthName}`,
                    icon: '💰',
                    body: 'Maintenance costs grouped by asset.',
                    rows: sorted.map(([assetNum, cost]) => {
                        const asset = assets.find(a => a.assetNum === assetNum);
                        const label = asset ? `${assetNum} – ${asset.assetDescription}` : assetNum;
                        return { label, value: `₱${cost.toLocaleString()}` };
                    })
                };
            }

            if (intent === 'asset_performance') {
                const performance = assets.map(a => {
                    const totalCost = (a.maintenanceHistory || []).reduce((sum, h) => sum + (h.cost || 0), 0);
                    const count = (a.maintenanceHistory || []).length;
                    const avgCost = count > 0 ? totalCost / count : 0;
                    return { asset: a, totalCost, count, avgCost };
                }).sort((a, b) => b.totalCost - a.totalCost);
                return {
                    type: 'orange',
                    title: 'Asset Performance Analysis',
                    icon: '📊',
                    body: 'Assets ranked by total maintenance cost.',
                    rows: performance.map(p => ({ 
                        label: `${p.asset.assetNum} – ${p.asset.assetDescription}`, 
                        value: `₱${p.totalCost.toLocaleString()} (${p.count} services)` 
                    }))
                };
            }

            // ── Fallback with Partial Keyword Match ────────────────────────────
            const qWords = q.split(/\s+/);
            const hasAssetWord = qWords.some(w => /asset|vehicle|truck|car|fleet|unit/.test(w));
            const hasInventoryWord = qWords.some(w => /inventory|stock|part|material|item/.test(w));
            const hasCostWord = qWords.some(w => /cost|expense|spend|spent|price|budget/.test(w));
            const hasPmsWord = qWords.some(w => /pms|preventive|maintenance|service|schedule/.test(w));

            if (hasAssetWord && assets.length > 0) {
                return {
                    type: 'blue',
                    title: 'All Registered Assets',
                    icon: '🚗',
                    body: `Here are all ${assets.length} asset(s) in the fleet.`,
                    rows: assets.map(a => ({ label: `${a.assetNum} – ${a.assetDescription}`, value: a.status || 'active' }))
                };
            }

            if (hasInventoryWord && inventory.length > 0) {
                return {
                    type: 'blue',
                    title: 'Inventory Items',
                    icon: '📦',
                    body: `${inventory.length} item(s) in inventory.`,
                    rows: inventory.slice(0, 20).map(i => ({ label: `${i.itemNum} – ${i.itemName}`, value: `${i.stock} ${i.unit}` }))
                };
            }

            if (hasCostWord) {
                const now = new Date();
                const thisMonth = now.getMonth();
                const thisYear = now.getFullYear();
                const monthTxns = serviceTransactions.filter(s => {
                    const d = new Date(s.dateServiced);
                    return d.getMonth() === thisMonth && d.getFullYear() === thisYear;
                });
                const total = monthTxns.reduce((sum, s) => sum + (s.totalCost || 0), 0);
                const monthName = now.toLocaleString('en-US', { month: 'long' });
                return {
                    type: 'green',
                    title: `Maintenance Costs – ${monthName}`,
                    icon: '💰',
                    body: `Total: ₱${total.toLocaleString()}`,
                    rows: monthTxns.map(s => ({ label: `${s.serviceId} – ${s.assetDescription}`, value: `₱${(s.totalCost || 0).toLocaleString()}` }))
                };
            }

            if (hasPmsWord) {
                const overdue = assets.filter(a => {
                    if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                    const due = new Date(a.nextPMSDue);
                    due.setHours(0, 0, 0, 0);
                    return due < today;
                }).length;
                const dueSoon = assets.filter(a => {
                    if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
                    const due = new Date(a.nextPMSDue);
                    due.setHours(0, 0, 0, 0);
                    const diff = Math.ceil((due - today) / 86400000);
                    return diff >= 0 && diff <= 14;
                }).length;
                return {
                    type: 'info',
                    title: 'PMS Summary',
                    icon: '🔧',
                    body: `Overdue: ${overdue} | Due soon (14 days): ${dueSoon}`,
                    rows: [
                        { label: 'Assets with PMS overdue', value: `${overdue}` },
                        { label: 'Assets with PMS due soon', value: `${dueSoon}` },
                        { label: 'Total assets', value: `${assets.length}` }
                    ]
                };
            }

            // ── Final Fallback ──────────────────────────────────────────────────
            return {
                type: 'info',
                title: 'No Matching Query',
                icon: '🤔',
                body: `Sorry, I couldn't understand "${query}". Try one of the suggested queries below or rephrase your question.`,
                rows: []
            };
        }
                const thisMonth = now.getMonth();
                const thisYear = now.getFullYear();
                const monthTxns = serviceTransactions.filter(s => {
                    const d = new Date(s.dateServiced);
                    return d.getMonth() === thisMonth && d.getFullYear() === thisYear;
                });
                const total = monthTxns.reduce((sum, s) => sum + (s.totalCost || 0), 0);
                const monthName = now.toLocaleString('en-US', { month: 'long' });
                return {
                    type: 'green',
                    title: `Total Repair Cost – ${monthName} ${thisYear}`,
                    icon: '💰',
                    body: `Total maintenance cost this month: ₱${total.toLocaleString()}`,
                    rows: monthTxns.map(s => ({ label: `${s.serviceId} – ${s.assetDescription}`, value: `₱${(s.totalCost || 0).toLocaleString()}` }))
                };
            
            // ── Frequently Maintained / Most Repaired ─────────────────────────
            if (q.includes('frequent') || q.includes('most maintained') || q.includes('most repaired') || q.includes('frequently')) {
                const counts = assets.map(a => ({
                    asset: a,
                    count: (a.maintenanceHistory || []).length
                })).sort((a, b) => b.count - a.count);
                return {
                    type: 'orange',
                    title: 'Most Frequently Maintained Assets',
                    icon: '🔧',
                    body: `Ranked by number of maintenance records on file.`,
                    rows: counts.map((c, i) => ({ label: `${i + 1}. ${c.asset.assetNum} – ${c.asset.assetDescription}`, value: `${c.count} record(s)` }))
                };
            }

            // ── Fast Moving Inventory ──────────────────────────────────────────
            if (q.includes('fast moving') || q.includes('most used') || q.includes('fast-moving')) {
                // Count usage from serviceTransactions spareParts
                const usageMap = {};
                serviceTransactions.forEach(s => {
                    (s.spareParts || []).forEach(p => {
                        usageMap[p.name] = (usageMap[p.name] || 0) + (p.quantity || 1);
                    });
                });
                const sorted = Object.entries(usageMap).sort((a, b) => b[1] - a[1]);
                if (sorted.length === 0) return { type: 'info', title: 'Fast Moving Inventory', icon: '📈', body: 'No issuance data available yet.', rows: [] };
                return {
                    type: 'purple',
                    title: 'Fast Moving Inventory Items',
                    icon: '📈',
                    body: 'Items ranked by total quantity used in service transactions.',
                    rows: sorted.map(([name, qty]) => ({ label: name, value: `${qty} units used` }))
                };
            }

            // ── Fallback ───────────────────────────────────────────────────────
            return {
                type: 'info',
                title: 'No Matching Query',
                icon: '🤔',
                body: `Sorry, I couldn't understand "${query}". Try one of the preset queries below or rephrase your question.`,
                rows: []
            };
        
        function renderSmartReportResult(result) {
            const container = document.getElementById('smartReportResult');
            const emptyState = document.getElementById('srEmptyState');

            // Hide empty state, show result
            if (emptyState) emptyState.style.display = 'none';
            container.style.display = 'block';

            const colorMap = {
                danger:  { bg: '#fff5f5', border: '#e53e3e', badge: '#fed7d7', badgeText: '#742a2a', header: '#e53e3e' },
                warning: { bg: '#fffbeb', border: '#d69e2e', badge: '#fefcbf', badgeText: '#744210', header: '#d69e2e' },
                success: { bg: '#f0fff4', border: '#38a169', badge: '#c6f6d5', badgeText: '#22543d', header: '#38a169' },
                green:   { bg: '#f0fff4', border: '#38a169', badge: '#c6f6d5', badgeText: '#22543d', header: '#38a169' },
                blue:    { bg: '#ebf8ff', border: '#3182ce', badge: '#bee3f8', badgeText: '#1a365d', header: '#3182ce' },
                orange:  { bg: '#fff5e6', border: '#ed8936', badge: '#feebc8', badgeText: '#7c2d12', header: '#ed8936' },
                purple:  { bg: '#faf5ff', border: '#805ad5', badge: '#e9d8fd', badgeText: '#44337a', header: '#805ad5' },
                info:    { bg: '#f7fafc', border: '#718096', badge: '#e2e8f0', badgeText: '#2d3748', header: '#718096' }
            };
            const c = colorMap[result.type] || colorMap.info;

            // Store last result for export
            window._lastSmartResult = result;

            const tableHtml = result.rows.length > 0 ? `
                <div style="border-radius:10px;overflow:hidden;border:1px solid #e2e8f0;margin-top:1rem;">
                    <table style="width:100%;border-collapse:collapse;background:white;">
                        <thead>
                            <tr style="background:${c.header};">
                                <th style="padding:0.75rem 1rem;text-align:left;color:white;font-size:0.8rem;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;width:40px;">#</th>
                                <th style="padding:0.75rem 1rem;text-align:left;color:white;font-size:0.8rem;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;">Item</th>
                                <th style="padding:0.75rem 1rem;text-align:right;color:white;font-size:0.8rem;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;">Value</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${result.rows.map((r, i) => `
                                <tr style="background:${i % 2 === 0 ? '#f9fafb' : 'white'};border-bottom:1px solid #e2e8f0;transition:background 0.15s;" onmouseover="this.style.background='#edf2f7'" onmouseout="this.style.background='${i % 2 === 0 ? '#f9fafb' : 'white'}'">
                                    <td style="padding:0.8rem 1rem;color:#a0aec0;font-size:0.82rem;font-weight:600;">${i + 1}</td>
                                    <td style="padding:0.8rem 1rem;font-weight:600;color:#1a202c;font-size:0.92rem;">${r.label}</td>
                                    <td style="padding:0.8rem 1rem;text-align:right;">
                                        <span style="background:${c.badge};color:${c.badgeText};padding:0.3rem 0.85rem;border-radius:20px;font-size:0.82rem;font-weight:700;white-space:nowrap;">${r.value}</span>
                                    </td>
                                </tr>`).join('')}
                        </tbody>
                    </table>
                </div>
                <div style="margin-top:0.6rem;font-size:0.8rem;color:#a0aec0;text-align:right;">${result.rows.length} result(s) found</div>` : '';

            const exportButtons = result.rows.length > 0 ? `
                <div style="display:flex;gap:0.6rem;margin-top:1.25rem;padding-top:1rem;border-top:1px solid rgba(0,0,0,0.07);">
                    <button onclick="exportSmartReportPDF()" class="btn-icon" style="background:#e53e3e;color:white;padding:0.55rem 1.1rem;font-size:0.85rem;border-radius:8px;font-weight:600;display:flex;align-items:center;gap:0.4rem;">
                        📄 Export PDF
                    </button>
                    <button onclick="exportSmartReportExcel()" class="btn-icon" style="background:#38a169;color:white;padding:0.55rem 1.1rem;font-size:0.85rem;border-radius:8px;font-weight:600;display:flex;align-items:center;gap:0.4rem;">
                        📊 Export Excel
                    </button>
                </div>` : '';

            container.innerHTML = `
                <div class="smart-result-card" style="border-left-color:${c.border};background:${c.bg};">
                    <div style="display:flex;align-items:center;gap:0.75rem;margin-bottom:0.5rem;">
                        <span style="font-size:1.75rem;">${result.icon}</span>
                        <div>
                            <div style="font-size:1.1rem;font-weight:800;color:#1a202c;">${result.title}</div>
                            <div style="font-size:0.9rem;color:#4a5568;margin-top:0.2rem;">${result.body}</div>
                        </div>
                    </div>
                    ${tableHtml}
                    ${exportButtons}
                </div>`;
        }

        function exportSmartReportPDF() {
            const result = window._lastSmartResult;
            if (!result) return;

            const date = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
            const rowsHtml = result.rows.map((r, i) => `
                <tr style="background:${i % 2 === 0 ? '#f9fafb' : 'white'};">
                    <td style="padding:10px 14px;border-bottom:1px solid #e2e8f0;font-weight:600;color:#1a202c;">${r.label}</td>
                    <td style="padding:10px 14px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:700;color:#2d3748;">${r.value}</td>
                </tr>`).join('');

            const win = window.open('', '_blank');
            win.document.write(`
                <!DOCTYPE html><html><head>
                <title>${result.title}</title>
                <style>
                    body { font-family: 'Segoe UI', sans-serif; margin: 40px; color: #1a202c; }
                    h1 { font-size: 1.5rem; margin-bottom: 0.25rem; }
                    .subtitle { color: #718096; font-size: 0.95rem; margin-bottom: 1.5rem; }
                    .meta { font-size: 0.82rem; color: #a0aec0; margin-bottom: 1.5rem; }
                    table { width: 100%; border-collapse: collapse; }
                    th { background: #1a202c; color: white; padding: 10px 14px; text-align: left; font-size: 0.85rem; }
                    th:last-child { text-align: right; }
                    @media print { button { display: none; } }
                </style>
                </head><body>
                <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:1.5rem;">
                    <div>
                        <div style="font-size:0.8rem;color:#E31E24;font-weight:700;text-transform:uppercase;letter-spacing:1px;margin-bottom:0.3rem;">Caltex San Pedro · JA Noble Enterprise Inc.</div>
                        <h1>${result.icon} ${result.title}</h1>
                        <div class="subtitle">${result.body}</div>
                        <div class="meta">Generated: ${date}</div>
                    </div>
                </div>
                <table>
                    <thead><tr><th>Item</th><th style="text-align:right;">Value</th></tr></thead>
                    <tbody>${rowsHtml}</tbody>
                </table>
                <div style="margin-top:2rem;font-size:0.8rem;color:#a0aec0;border-top:1px solid #e2e8f0;padding-top:1rem;">
                    Total: ${result.rows.length} result(s) &nbsp;|&nbsp; Smart Reports – Caltex San Pedro · JA Noble Enterprise Inc.
                </div>
                <br><button onclick="window.print()" style="background:#E31E24;color:white;padding:0.6rem 1.5rem;border:none;border-radius:8px;font-size:1rem;cursor:pointer;font-weight:600;">🖨️ Print / Save as PDF</button>
                </body></html>`);
            win.document.close();
        }

        function exportSmartReportExcel() {
            const result = window._lastSmartResult;
            if (!result) return;

            const date = new Date().toLocaleDateString('en-US');
            const query = document.getElementById('smartQueryInput').value || result.title;

            // Build CSV content
            const lines = [
                ['Caltex San Pedro · JA Noble Enterprise Inc. – Smart Reports'],
                [`Report: ${result.title}`],
                [`Summary: ${result.body}`],
                [`Generated: ${date}`],
                [''],
                ['Item', 'Value'],
                ...result.rows.map(r => [r.label, r.value]),
                [''],
                [`Total Results: ${result.rows.length}`]
            ];

            const csv = lines.map(row =>
                row.map(cell => `"${String(cell).replace(/"/g, '""')}"`).join(',')
            ).join('\r\n');

            const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `smart-report-${result.title.replace(/\s+/g, '-').toLowerCase()}-${date.replace(/\//g, '-')}.csv`;
            a.click();
            URL.revokeObjectURL(url);
        }
