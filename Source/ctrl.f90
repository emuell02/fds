MODULE CONTROL_FUNCTIONS

! Routines for evaluating control functions

USE PRECISION_PARAMETERS
USE CONTROL_VARIABLES
USE GLOBAL_CONSTANTS, ONLY : EVACUATION_ONLY,UPDATE_DEVICES_AGAIN
USE DEVICE_VARIABLES

IMPLICIT NONE

CONTAINS

SUBROUTINE UPDATE_CONTROLS(T,DT,CTRL_STOP_STATUS,RUN_START)

! Update the value of all sensing DEVICEs and associated output quantities

REAL(EB), INTENT(IN) :: T,DT
INTEGER :: NC,N
LOGICAL :: CTRL_STOP_STATUS
LOGICAL, INTENT(IN) :: RUN_START
TYPE(DEVICE_TYPE), POINTER :: DV=>NULL()

CTRL_STOP_STATUS = .FALSE.

CONTROL_LOOP_1: DO NC=1,N_CTRL
   IF (.NOT. RUN_START .AND. CONTROL(NC)%LATCH .AND. (CONTROL(NC)%INITIAL_STATE .NEQV. CONTROL(NC)%CURRENT_STATE)) THEN
      CONTROL(NC)%UPDATED = .TRUE.
      CONTROL(NC)%PRIOR_STATE = CONTROL(NC)%CURRENT_STATE
   ELSE
      CONTROL(NC)%UPDATED = .FALSE.
   ENDIF
END DO CONTROL_LOOP_1
CONTROL_LOOP_2: DO NC=1,N_CTRL
   IF (CONTROL(NC)%UPDATED) CYCLE CONTROL_LOOP_2
   IF (ALL(EVACUATION_ONLY)) CYCLE CONTROL_LOOP_2
   CALL EVALUATE_CONTROL(T,NC,DT,CTRL_STOP_STATUS)
END DO CONTROL_LOOP_2

! Update devices that are used to print out control function results only for devices that require an 'INSTANT VALUE'; 
! that is, a value from this current time step.

IF (UPDATE_DEVICES_AGAIN) THEN
   DEVICE_LOOP: DO N=1,N_DEVC
      DV => DEVICE(N)
      IF (DV%TEMPORAL_STATISTIC/='INSTANT VALUE') CYCLE DEVICE_LOOP
      SELECT CASE(DV%QUANTITY)
         CASE('CONTROL VALUE')
            DV%VALUE = CONTROL(DV%CTRL_INDEX)%INSTANT_VALUE * DV%CONVERSION_FACTOR
            DV%TIME_INTERVAL = 1._EB
         CASE('CONTROL')
            DV%VALUE = 0._EB
            IF (CONTROL(DV%CTRL_INDEX)%CURRENT_STATE) DV%VALUE = 1._EB
            DV%TIME_INTERVAL = 1._EB
      END SELECT
   ENDDO DEVICE_LOOP
ENDIF

END SUBROUTINE UPDATE_CONTROLS

RECURSIVE SUBROUTINE EVALUATE_CONTROL(T,ID,DT,CTRL_STOP_STATUS)

! Update the value of all sensing DEVICEs and associated output quantities

USE MATH_FUNCTIONS, ONLY: EVALUATE_RAMP
USE GLOBAL_CONSTANTS, ONLY: RESTART_CLOCK
REAL(EB), INTENT(IN) :: T,DT
REAL(EB) :: RAMP_VALUE,T_CHANGE,RAMP_INPUT,PID_VALUE
INTEGER :: NC,COUNTER
INTEGER, INTENT(IN) :: ID
TYPE(CONTROL_TYPE), POINTER :: CF=>NULL()
TYPE(DEVICE_TYPE), POINTER :: DV=>NULL()
LOGICAL :: STATE1, STATE2, CTRL_STOP_STATUS

CF => CONTROL(ID)
CF%PRIOR_STATE = CF%CURRENT_STATE
T_CHANGE = -1.E6_EB
STATE2 = .FALSE.
CONTROL_SELECT: SELECT CASE (CF%CONTROL_INDEX)
   CASE (AND_GATE)
      DO NC = 1, CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               IF (T >T_CHANGE) CF%MESH = DV%MESH
               T_CHANGE = T
               STATE1 = DV%CURRENT_STATE
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) THEN
                  CALL EVALUATE_CONTROL(T,CF%INPUT(NC),DT,CTRL_STOP_STATUS)
                  CF => CONTROL(ID)
               ENDIF
               STATE1 = CONTROL(CF%INPUT(NC))%CURRENT_STATE
               IF (T > T_CHANGE) CF%MESH=CONTROL(CF%INPUT(NC))%MESH
               T_CHANGE = T
         END SELECT
         IF (NC==1) THEN
            STATE2 = STATE1
         ELSE
            STATE2 = STATE1 .AND. STATE2
         ENDIF
      ENDDO

  CASE (OR_GATE)
      DO NC = 1, CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               IF (T>T_CHANGE) CF%MESH = DV%MESH
               T_CHANGE = T
               STATE1 = DV%CURRENT_STATE
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) THEN
                  CALL EVALUATE_CONTROL(T,CF%INPUT(NC),DT,CTRL_STOP_STATUS)
                  CF => CONTROL(ID)
               ENDIF
               STATE1 = CONTROL(CF%INPUT(NC))%CURRENT_STATE
               IF (T > T_CHANGE) CF%MESH=CONTROL(CF%INPUT(NC))%MESH
               T_CHANGE = T
         END SELECT
         IF (NC==1) THEN
            STATE2 = STATE1
         ELSE
            STATE2 = STATE1 .OR. STATE2
         ENDIF
      ENDDO

   CASE (XOR_GATE)
      COUNTER = 0
      DO NC = 1, CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               IF (DV%CURRENT_STATE) THEN
                  COUNTER = COUNTER + 1
                  IF (T >T_CHANGE) THEN
                     CF%MESH = DV%MESH
                     T_CHANGE = T
                  ENDIF
               ENDIF
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) THEN
                  CALL EVALUATE_CONTROL(T,CF%INPUT(NC),DT,CTRL_STOP_STATUS)
                  CF => CONTROL(ID)
               ENDIF
               IF (CONTROL(CF%INPUT(NC))%CURRENT_STATE) THEN
                  COUNTER = COUNTER + 1
                  IF (T > T_CHANGE) CF%MESH=CONTROL(CF%INPUT(NC))%MESH
                  T_CHANGE = T
               ENDIF
         END SELECT
      ENDDO
      IF (COUNTER==CF%N) STATE2 = .TRUE.
   CASE (X_OF_N_GATE)
      COUNTER = 0
      DO NC = 1, CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               IF (DV%CURRENT_STATE) THEN
                  COUNTER = COUNTER + 1
                  IF (T>T_CHANGE) CF%MESH = DV%MESH
                  T_CHANGE = T
               ENDIF
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) THEN
                  CALL EVALUATE_CONTROL(T,CF%INPUT(NC),DT,CTRL_STOP_STATUS)
                  CF => CONTROL(ID)
               ENDIF
               IF (CONTROL(CF%INPUT(NC))%CURRENT_STATE) THEN
                  COUNTER = COUNTER + 1
                  IF (T > T_CHANGE) CF%MESH=CONTROL(CF%INPUT(NC))%MESH
                  T_CHANGE = T
               ENDIF
         END SELECT
      ENDDO
      IF (COUNTER>=CF%N) STATE2 = .TRUE.

   CASE (DEADBAND)
       DV => DEVICE(CF%INPUT(1))
       T_CHANGE = T
       CF%MESH = DV%MESH
       IF (CF%ON_BOUND > 0) THEN
          IF (DV%SMOOTHED_VALUE > CF%SETPOINT(2) .AND. (CF%CURRENT_STATE .EQV. CF%INITIAL_STATE)) THEN
             STATE2 = .TRUE.
          ELSEIF(DV%SMOOTHED_VALUE < CF%SETPOINT(1) .AND. (CF%CURRENT_STATE .NEQV. CF%INITIAL_STATE)) THEN
             STATE2 = .FALSE.
          ELSEIF(DV%SMOOTHED_VALUE >= CF%SETPOINT(1) .AND. (CF%CURRENT_STATE .NEQV. CF%INITIAL_STATE)) THEN
             STATE2 = .TRUE.
          ENDIF
       ELSE
          IF (DV%SMOOTHED_VALUE < CF%SETPOINT(1) .AND. (CF%CURRENT_STATE .EQV. CF%INITIAL_STATE)) THEN
             STATE2 = .TRUE.
          ELSEIF(DV%SMOOTHED_VALUE > CF%SETPOINT(2) .AND. (CF%CURRENT_STATE .NEQV. CF%INITIAL_STATE)) THEN
             STATE2 = .FALSE.
          ELSEIF(DV%SMOOTHED_VALUE <= CF%SETPOINT(2) .AND. (CF%CURRENT_STATE .NEQV. CF%INITIAL_STATE)) THEN
             STATE2 = .TRUE.
          ENDIF
       ENDIF

   CASE (TIME_DELAY)
      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%MESH = DV%MESH
            CF%INSTANT_VALUE = T - DV%T_CHANGE
            IF (CF%INSTANT_VALUE >= CF%DELAY .AND. CF%T_CHANGE <= DV%T_CHANGE) CF%CURRENT_STATE = .NOT. CF%PRIOR_STATE
            T_CHANGE = T
         CASE (CONTROL_INPUT)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = T - CONTROL(CF%INPUT(1))%T_CHANGE
            IF (CF%INSTANT_VALUE >= CF%DELAY .AND. CF%T_CHANGE <= CONTROL(CF%INPUT(1))%T_CHANGE) &
               CF%CURRENT_STATE = .NOT. CF%PRIOR_STATE
            T_CHANGE = T
         END SELECT
      ! Special case first flip
      IF ( CF%INSTANT_VALUE >= CF%DELAY .AND. ABS(CF%T_CHANGE-1000000._EB) <= TWO_EPSILON_EB) &
         CF%CURRENT_STATE = .NOT. CF%PRIOR_STATE
   CASE (CYCLING)

   CASE (CUSTOM)
      STATE2 = .FALSE.
      DV => DEVICE(CF%INPUT(1))
      CF%MESH = DV%MESH
      RAMP_INPUT = DV%SMOOTHED_VALUE
      RAMP_VALUE = EVALUATE_RAMP(RAMP_INPUT,0._EB,CF%RAMP_INDEX)
      CF%INSTANT_VALUE = RAMP_VALUE
      IF (RAMP_VALUE > 0._EB) STATE2 = .TRUE.
      T_CHANGE = T

   CASE (KILL)
      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%MESH = DV%MESH
            T_CHANGE = T
            STATE2 = DV%CURRENT_STATE
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            STATE2 = CONTROL(CF%INPUT(1))%CURRENT_STATE
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
            T_CHANGE = T
      END SELECT
      IF (STATE2) CTRL_STOP_STATUS=.TRUE.

   CASE (CORE_DUMP)
      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%MESH = DV%MESH
            T_CHANGE = T
            STATE2 = DV%CURRENT_STATE
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            STATE2 = CONTROL(CF%INPUT(1))%CURRENT_STATE
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
            T_CHANGE = T
      END SELECT
      IF (STATE2) RESTART_CLOCK = T_CHANGE

   CASE (CF_SUM)
      CF%INSTANT_VALUE=0._EB
      DO NC = 1,CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               CF%INSTANT_VALUE = CF%INSTANT_VALUE + DV%SMOOTHED_VALUE
               CF%MESH = DV%MESH
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) THEN
                  CALL EVALUATE_CONTROL(T,CF%INPUT(NC),DT,CTRL_STOP_STATUS)
                  CF => CONTROL(ID)
               ENDIF
               CF%MESH=CONTROL(CF%INPUT(NC))%MESH
               CF%INSTANT_VALUE = CF%INSTANT_VALUE + CONTROL(CF%INPUT(NC))%INSTANT_VALUE
            CASE (CONSTANT_INPUT)
               CF%INSTANT_VALUE = CF%INSTANT_VALUE + CF%CONSTANT
         END SELECT
      END DO
      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_SUBTRACT)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = DV%SMOOTHED_VALUE
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
            CF%INSTANT_VALUE = CONTROL(CF%INPUT(1))%INSTANT_VALUE
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = CF%CONSTANT
      END SELECT

      SELECT CASE (CF%INPUT_TYPE(2))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(2))
            CF%INSTANT_VALUE = CF%INSTANT_VALUE - DV%SMOOTHED_VALUE
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(2))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(2),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%MESH=CONTROL(CF%INPUT(2))%MESH
            CF%INSTANT_VALUE = CF%INSTANT_VALUE - CONTROL(CF%INPUT(2))%INSTANT_VALUE
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = CF%INSTANT_VALUE - CF%CONSTANT
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_MULTIPLY)
      CF%INSTANT_VALUE=1._EB
      DO NC = 1,CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               CF%INSTANT_VALUE = CF%INSTANT_VALUE * DV%SMOOTHED_VALUE
               CF%MESH = DV%MESH
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) THEN
                  CALL EVALUATE_CONTROL(T,CF%INPUT(NC),DT,CTRL_STOP_STATUS)
                  CF => CONTROL(ID)
               ENDIF
               CF%MESH=CONTROL(CF%INPUT(NC))%MESH
               CF%INSTANT_VALUE = CF%INSTANT_VALUE * CONTROL(CF%INPUT(NC))%INSTANT_VALUE
            CASE (CONSTANT_INPUT)
               CF%INSTANT_VALUE = CF%INSTANT_VALUE * CF%CONSTANT
         END SELECT
      END DO
      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_DIVIDE)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = DV%SMOOTHED_VALUE
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
            CF%INSTANT_VALUE = CONTROL(CF%INPUT(1))%INSTANT_VALUE
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = CF%CONSTANT
      END SELECT

      SELECT CASE (CF%INPUT_TYPE(2))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(2))
            CF%INSTANT_VALUE = CF%INSTANT_VALUE / DV%SMOOTHED_VALUE
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(2))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(2),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%MESH=CONTROL(CF%INPUT(2))%MESH
            CF%INSTANT_VALUE = CF%INSTANT_VALUE / CONTROL(CF%INPUT(2))%INSTANT_VALUE
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = CF%INSTANT_VALUE / CF%CONSTANT
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_POWER)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = DV%SMOOTHED_VALUE
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = CONTROL(CF%INPUT(1))%INSTANT_VALUE
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = CF%CONSTANT
      END SELECT

      SELECT CASE (CF%INPUT_TYPE(2))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(2))
            CF%INSTANT_VALUE = CF%INSTANT_VALUE ** DV%SMOOTHED_VALUE
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(2))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(2),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = CF%INSTANT_VALUE ** CONTROL(CF%INPUT(2))%INSTANT_VALUE
            CF%MESH=CONTROL(CF%INPUT(2))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = CF%INSTANT_VALUE ** CF%CONSTANT
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_PID)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = DV%SMOOTHED_VALUE - CF%TARGET_VALUE
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = CONTROL(CF%INPUT(1))%INSTANT_VALUE - CF%TARGET_VALUE
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
      END SELECT

      IF (CF%PREVIOUS_VALUE < -1.E30_EB) CF%PREVIOUS_VALUE = CF%INSTANT_VALUE
      CF%INTEGRAL = DT*CF%INSTANT_VALUE+CF%INTEGRAL
      PID_VALUE = CF%PROPORTIONAL_GAIN * CF%INSTANT_VALUE + &
                         CF%INTEGRAL_GAIN * CF%INTEGRAL + &
                         CF%DIFFERENTIAL_GAIN * (CF%INSTANT_VALUE - CF%PREVIOUS_VALUE) / (DT+1.E-20_EB)
      CF%PREVIOUS_VALUE = CF%INSTANT_VALUE
      CF%INSTANT_VALUE = PID_VALUE
      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_EXP)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = EXP(DV%SMOOTHED_VALUE)
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = EXP(CONTROL(CF%INPUT(1))%INSTANT_VALUE)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = EXP(CF%CONSTANT)
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_LOG)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = LOG(DV%SMOOTHED_VALUE)
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = LOG(CONTROL(CF%INPUT(1))%INSTANT_VALUE)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = LOG(CF%CONSTANT)
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_SIN)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = SIN(DV%SMOOTHED_VALUE)
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = SIN(CONTROL(CF%INPUT(1))%INSTANT_VALUE)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = SIN(CF%CONSTANT)
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

    CASE (CF_COS)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = COS(DV%SMOOTHED_VALUE)
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = COS(CONTROL(CF%INPUT(1))%INSTANT_VALUE)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = COS(CF%CONSTANT)
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_ASIN)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = ASIN(DV%SMOOTHED_VALUE)
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = ASIN(CONTROL(CF%INPUT(1))%INSTANT_VALUE)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = ASIN(CF%CONSTANT)
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_ACOS)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = ACOS(DV%SMOOTHED_VALUE)
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = ACOS(CONTROL(CF%INPUT(1))%INSTANT_VALUE)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = ACOS(CF%CONSTANT)
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

    CASE (CF_MIN)
      CF%INSTANT_VALUE=HUGE(TWO_EPSILON_EB)

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = MIN(DV%SMOOTHED_VALUE,CF%INSTANT_VALUE)
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = MIN(CF%INSTANT_VALUE,CONTROL(CF%INPUT(1))%INSTANT_VALUE)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = MIN(CF%INSTANT_VALUE,CF%CONSTANT)
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

    CASE (CF_MAX)
      CF%INSTANT_VALUE=-HUGE(TWO_EPSILON_EB)

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = MAX(DV%SMOOTHED_VALUE,CF%INSTANT_VALUE)
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = MAX(CF%INSTANT_VALUE,CONTROL(CF%INPUT(1))%INSTANT_VALUE)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = MAX(CF%INSTANT_VALUE,CF%CONSTANT)
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

   CASE (CF_ABS)
      CF%INSTANT_VALUE=0._EB

      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%INSTANT_VALUE = ABS(DV%SMOOTHED_VALUE)
            CF%MESH = DV%MESH
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) THEN
               CALL EVALUATE_CONTROL(T,CF%INPUT(1),DT,CTRL_STOP_STATUS)
               CF => CONTROL(ID)
            ENDIF
            CF%INSTANT_VALUE = ABS(CONTROL(CF%INPUT(1))%INSTANT_VALUE)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
         CASE (CONSTANT_INPUT)
            CF%INSTANT_VALUE = ABS(CF%CONSTANT)
      END SELECT

      IF (CF%INSTANT_VALUE > CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION > 0) THEN
         STATE2 = .TRUE.
      ELSEIF (CF%INSTANT_VALUE < CF%SETPOINT(1) .AND. CF%TRIP_DIRECTION < 0) THEN
         STATE2 = .TRUE.
      ENDIF
      T_CHANGE = T

END SELECT CONTROL_SELECT

IF (CF%CONTROL_INDEX/=TIME_DELAY) THEN
   IF (STATE2) THEN
      CF%CURRENT_STATE = .NOT. CF%INITIAL_STATE
   ELSE
      CF%CURRENT_STATE = CF%INITIAL_STATE
   ENDIF
ENDIF

IF(CF%CURRENT_STATE .NEQV. CF%PRIOR_STATE) CF%T_CHANGE = T_CHANGE

CF%UPDATED = .TRUE.

END SUBROUTINE EVALUATE_CONTROL

END MODULE CONTROL_FUNCTIONS
