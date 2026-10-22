namespace AmbulanceWay.Constants
{
    public static class AppConstants
    {
        // User Roles
        public const string RoleAdmin = "ADMIN";
        public const string RoleDriver = "DRIVER";
        public const string RoleHospital = "HOSPITAL"; // For HospitalUser
        public const string RolePatient = "PATIENT";
        public const string RoleAdminsGroup = "Admins"; // SignalR group name for Admins
        public const string RoleDriversGroup = "Drivers"; // SignalR group name for Drivers

        // User/Driver/Hospital Status
        public const string StatusActive = "ACTIVE";
        public const string StatusInactive = "INACTIVE";
        public const string StatusOnline = "ONLINE";
        public const string StatusOffline = "OFFLINE";
        public const string StatusLocked = "LOCKED";

        // Emergency Case Status
        public const string CaseStatusPending = "PENDING";
        public const string CaseStatusDispatching = "DISPATCHING";
        public const string CaseStatusAssigned = "ASSIGNED";
        public const string CaseStatusAccepted = "ACCEPTED";
        public const string CaseStatusPickedUp = "PICKED_UP";
        public const string CaseStatusDelivering = "DELIVERING";
        public const string CaseStatusCompleted = "COMPLETED";
        public const string CaseStatusCancelled = "CANCELLED";
        public const string CaseStatusRejected = "REJECTED";

        // Hospital Reception Status
        public const string HospitalReceptionOpen = "OPEN";
        public const string HospitalReceptionFull = "FULL";
        public const string HospitalReceptionClosed = "CLOSED";

        // Session Keys
        public const string SessionUsername = "USERNAME";
        public const string SessionRole = "ROLE";
        public const string SessionStaff = "STAFF";
        public const string SessionHospitalId = "HOSPITAL_ID";
        public const string SessionHospitalName = "HOSPITAL_NAME";
        public const string SessionHospitalUsername = "HOSPITAL_USERNAME";
        public const string SessionVehicle = "VEHICLE";
        public const string SessionPhone = "PHONE";
        public const string SessionShiftStart = "SHIFT_START";
        public const string SessionStation = "STATION";
        public const string SessionStationLat = "STATION_LAT";
        public const string SessionStationLng = "STATION_LNG";

        // Numeric Role Values for Session
        public const int RoleValueAdmin = 1;
        public const int RoleValueDriver = 2;
        public const int RoleValueHospital = 3;
        public const int RoleValuePatient = 4;

        // SignalR Event Names
        public const string SignalRReceiveNewTrip = "ReceiveNewTrip";
        public const string SignalRDriverLocationUpdate = "DriverLocationUpdate";
        public const string SignalRNotifyCaseAccepted = "NotifyCaseAccepted";
        public const string SignalRCaseAlreadyTaken = "CaseAlreadyTaken";
        public const string SignalRTripStatusUpdated = "TripStatusUpdated";
        public const string SignalRHospitalConfirmed = "HospitalConfirmed";
        public const string SignalRReceiveEmergencyCall = "ReceiveEmergencyCall";
        public const string SignalRReceiveIncomingPatient = "ReceiveIncomingPatient";
        public const string SignalRCaseStatusUpdated = "CaseStatusUpdated";
        public const string SignalRHospitalCapacityUpdated = "HospitalCapacityUpdated";
        public const string SignalREscalationAlert = "EscalationAlert";
        public const string SignalRCaseCancelled = "CaseCancelled";
    }
}