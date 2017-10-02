












!=======================================================================
!
!BOP
!
! !MODULE: ice_step_mod
!
! !DESCRIPTION:
!
!  Contains CICE component driver routines common to all drivers.
!
! !REVISION HISTORY:
!  SVN:$Id$
!
!  authors Elizabeth C. Hunke, LANL
!          Philip W. Jones, LANL
!          William H. Lipscomb, LANL
!
! 2008 ECH: created module by moving subroutines from drivers/cice4/
!
! !INTERFACE:
!
      module ice_step_mod
!
! !USES:
!
!      use ice_age
      use ice_atmo
      use ice_calendar
      use ice_communicate
      use ice_diagnostics
      use ice_domain
      use ice_dyn_evp
!      use ice_exit
      use ice_fileunits
      use ice_flux
      use ice_forcing
      use ice_grid
      use ice_history
      use ice_restart
      use ice_itd
      use ice_kinds_mod
      use ice_mechred
      use ice_meltpond
      use ice_ocean
      use ice_orbital
      use ice_shortwave
      use ice_state
      use ice_therm_itd
      use ice_therm_vertical
      use ice_timers
      use ice_transport_driver
      use ice_constants
      use ice_transport_remap
      use ice_exit, only: abort_ice

      implicit none
      private
      save

! !PUBLIC MEMBER FUNCTIONS:

      public :: step_therm2, step_dynamics,  &
                cleanup_itd_before_dynamics, &
                incremental_update_skin,     &
                prep_radiation, step_radiation
!
!EOP
!
!=======================================================================

      contains

!=======================================================================
!BOP
!
! !ROUTINE: prep_radiation
!
! !DESCRIPTION:
!
! Scales radiation fields computed on the previous time step.
!
! !REVISION HISTORY:
!
! authors: David A. Bailey, NCAR
!
! !INTERFACE:

      subroutine prep_radiation (dt)
!
! !USES:
!
! !INPUT/OUTPUT PARAMETERS:
!
      real (kind=dbl_kind), intent(in) :: &
         dt      ! time step
!
!EOP
!
      integer (kind=int_kind) :: &
         i, j, ij    , & ! horizontal indices
         iblk        , & ! block index
         ilo,ihi,jlo,jhi, & ! beginning and end of physical domain
         n           , & ! thickness category index
         il1, il2    , & ! ice layer indices for eice
         sl1, sl2        ! snow layer indices for esno

      integer (kind=int_kind) :: &
         icells          ! number of cells with aicen > puny

      integer (kind=int_kind), dimension(nx_block*ny_block) :: &
         indxi, indxj    ! indirect indices for cells with aicen > puny

      real (kind=dbl_kind) :: netsw 

      type (block) :: &
         this_block      ! block information for current block

      logical (kind=log_kind) :: &
         l_stop          ! if true, abort the model

      integer (kind=int_kind) :: &
         istop, jstop    ! indices of grid cell where model aborts 

      call ice_timer_start(timer_column)  ! column physics
      call ice_timer_start(timer_thermo)  ! thermodynamics
      call ice_timer_start(timer_sw)      ! shortwave

      l_stop = .false.

      if (calc_Tsfc) then

      do iblk = 1, nblocks
         this_block = get_block(blocks_ice(iblk),iblk)         
         ilo = this_block%ilo
         ihi = this_block%ihi
         jlo = this_block%jlo
         jhi = this_block%jhi

      !-----------------------------------------------------------------
      ! Compute netsw scaling factor (new netsw / old netsw)
      !-----------------------------------------------------------------

         do j = jlo, jhi
         do i = ilo, ihi
            if (aice(i,j,iblk) > c0 .and. scale_factor(i,j,iblk) > puny) then
               netsw = swvdr(i,j,iblk)*(c1 - alvdr_gbm(i,j,iblk)) &
                     + swvdf(i,j,iblk)*(c1 - alvdf_gbm(i,j,iblk)) &
                     + swidr(i,j,iblk)*(c1 - alidr_gbm(i,j,iblk)) &
                     + swidf(i,j,iblk)*(c1 - alidf_gbm(i,j,iblk))
               scale_factor(i,j,iblk) = netsw / scale_factor(i,j,iblk)
            else
               scale_factor(i,j,iblk) = c1
            endif
            fswfac(i,j,iblk) = scale_factor(i,j,iblk) ! for history 
         enddo               ! i
         enddo               ! j

         do n = 1, ncat

      !-----------------------------------------------------------------
      ! Identify cells with nonzero ice area
      !-----------------------------------------------------------------
           
            icells = 0
            do j = jlo, jhi
            do i = ilo, ihi
               if (aicen(i,j,n,iblk) > puny) then
                  icells = icells + 1
                  indxi(icells) = i
                  indxj(icells) = j
               endif
            enddo               ! i
            enddo               ! j

      !-----------------------------------------------------------------
      ! Scale absorbed solar radiation for change in net shortwave
      !-----------------------------------------------------------------

            il1 = ilyr1(n)
            il2 = ilyrn(n)
            sl1 = slyr1(n)
            sl2 = slyrn(n)

            do ij = 1, icells
               i = indxi(ij)
               j = indxj(ij)

               fswsfcn(i,j,n,iblk)  = scale_factor(i,j,iblk)*fswsfcn (i,j,n,iblk)
               fswintn(i,j,n,iblk)  = scale_factor(i,j,iblk)*fswintn (i,j,n,iblk)
               fswthrun(i,j,n,iblk) = scale_factor(i,j,iblk)*fswthrun(i,j,n,iblk)
               Sswabsn(i,j,sl1:sl2,iblk) = &
                       scale_factor(i,j,iblk)*Sswabsn(i,j,sl1:sl2,iblk)
               Iswabsn(i,j,il1:il2,iblk) = &
                       scale_factor(i,j,iblk)*Iswabsn(i,j,il1:il2,iblk)
            enddo
         enddo                  ! ncat
      enddo                      ! iblk

      else    ! .not. calc_Tsfc

         ! Initialize for safety
         do iblk = 1, nblocks
         do n = 1, ncat
         do j = 1, ny_block
         do i = 1, nx_block
            fswsfcn(i,j,n,iblk) = c0
            fswintn(i,j,n,iblk) = c0
            fswthrun(i,j,n,iblk) = c0
         enddo   ! i
         enddo   ! j
         enddo   ! ncat
            Iswabsn(:,:,:,iblk) = c0
            Sswabsn(:,:,:,iblk) = c0
         enddo   ! iblk

      endif    ! calc_Tsfc

      call ice_timer_stop(timer_sw)     ! shortwave
      call ice_timer_stop(timer_thermo) ! thermodynamics
      call ice_timer_stop(timer_column) ! column physics

      end subroutine prep_radiation

!=======================================================================
!BOP
!
! !ROUTINE: step_therm2 - step post-coupler thermodynamics
!
! !DESCRIPTION:
!
!-----------------------------------------------------------------------
! Driver for thermodynamic changes not needed for coupling:
! transport in thickness space, lateral growth and melting.
!
! NOTE: Ocean fluxes are initialized here.
!
! !REVISION HISTORY:
!
! author: William H. Lipscomb, LANL
!
! !INTERFACE:

      subroutine step_therm2 (dt)
!
! !USES:
!
! !INPUT/OUTPUT PARAMETERS:
!
      real (kind=dbl_kind), intent(in) :: &
         dt      ! time step
!
!EOP
!
!lipscomb - delete hicen later?
!      real (kind=dbl_kind), &
!         dimension (nx_block,ny_block,ncat,max_blocks) :: &

      integer (kind=int_kind) :: &
         iblk        , & ! block index
         ilo,ihi,jlo,jhi, & ! beginning and end of physical domain
         i, j, n

      integer (kind=int_kind) :: &
         icells          ! number of ice/ocean cells 

      integer (kind=int_kind), dimension(nx_block*ny_block) :: &
         indxi, indxj    ! indirect indices for ice/ocean cells

      type (block) :: &
         this_block      ! block information for current block

      real (kind=real_kind), dimension (nx_block,ny_block) :: &
         latd, lond  

      logical (kind=log_kind) :: &
         l_stop          ! if true, abort model

      integer (kind=int_kind) :: &
         istop, jstop    ! indices of grid cell where model aborts

      call ice_timer_start(timer_column)  ! column physics
      call ice_timer_start(timer_thermo)  ! thermodynamics

      l_stop = .false.
      
      do iblk = 1, nblocks
         this_block = get_block(blocks_ice(iblk),iblk)         
         ilo = this_block%ilo
         ihi = this_block%ihi
         jlo = this_block%jlo
         jhi = this_block%jhi

      !-----------------------------------------------------------------
      ! Let rain drain through to the ocean.
      !-----------------------------------------------------------------

         do j = 1, ny_block
         do i = 1, nx_block
            fresh     (i,j,iblk) = fresh(i,j,iblk)       &
                                 + frain(i,j,iblk)*aice(i,j,iblk)
         enddo
         enddo

      !-----------------------------------------------------------------
      ! Given thermodynamic growth rates, transport ice between
      ! thickness categories.
      !-----------------------------------------------------------------

         call ice_timer_start(timer_catconv)    ! category conversions

         if (kitd == 1) then
      !-----------------------------------------------------------------
      ! Compute fractional ice area in each grid cell.
      !-----------------------------------------------------------------
            call aggregate_area (nx_block,          ny_block, &
                                 aicen(:,:,:,iblk),           &
                                 aice (:,:,  iblk), aice0(:,:,iblk))

      !-----------------------------------------------------------------
      ! Identify grid cells with ice.
      !-----------------------------------------------------------------

            icells = 0
            do j = jlo,jhi
            do i = ilo,ihi
               if (aice(i,j,iblk) > puny) then
                  icells = icells + 1
                  indxi(icells) = i
                  indxj(icells) = j
               endif
            enddo
            enddo

            if (icells > 0) then

            call linear_itd (nx_block, ny_block,       &
                             icells, indxi, indxj,     &
                             trcr_depend,    &
                             aicen_init(:,:,:,iblk),   &
                             vicen_init(:,:,:,iblk),   &
                             aicen     (:,:,:,iblk),   &
                             trcrn     (:,:,:,:,iblk), & 
                             vicen     (:,:,:,iblk),   &
                             vsnon     (:,:,:,iblk),   &
                             eicen     (:,:,:,iblk),   &
                             esnon     (:,:,:,iblk),   &
                             aice      (:,:,  iblk),   &
                             aice0     (:,:,  iblk),   &
                             latd,     lond,           &
                             l_stop,                   &
                             istop,    jstop)

            if (l_stop) then
               write (nu_diag,*) 'istep1, my_task, iblk =', &
                                  istep1, my_task, iblk
               write (nu_diag,*) 'Global block:', this_block%block_id
               if (istop > 0 .and. jstop > 0) &
                    write(nu_diag,*) 'Global i and j:', &
                                     this_block%i_glob(istop), &
                                     this_block%j_glob(jstop) 
               call abort_ice ('ice: Linear ITD error')
            endif

            endif

         endif  ! kitd = 1

         call ice_timer_stop(timer_catconv)    ! category conversions

      !-----------------------------------------------------------------
      ! Add frazil ice growing in leads.
      !-----------------------------------------------------------------

         ! identify ice-ocean cells
         icells = 0
         do j = 1, ny_block
         do i = 1, nx_block
            if (tmask(i,j,iblk)) then
               icells = icells + 1
               indxi(icells) = i
               indxj(icells) = j
            endif
         enddo               ! i
         enddo               ! j

         call add_new_ice (nx_block,              ny_block, &
                           icells,                          &
                           indxi,                 indxj,    &
                           tmask     (:,:,  iblk), dt,      &
                           aicen     (:,:,:,iblk),          &
                           trcrn     (:,:,:,:,iblk),        &
                           vicen     (:,:,:,iblk),          &
                           eicen     (:,:,:,iblk),          &
                           aice0     (:,:,  iblk),          &
                           aice      (:,:,  iblk),          &
                           frzmlt    (:,:,  iblk),          &
                           frazil    (:,:,  iblk),          &
                           .false.,                         & 
                           frz_onset (:,:,  iblk), yday,    &
                           fresh     (:,:,  iblk),          &
                           fsalt     (:,:,  iblk),          &
                           Tf        (:,:,  iblk), l_stop,  &
                           istop                 , jstop)

         if (l_stop) then
            write (nu_diag,*) 'istep1, my_task, iblk =', &
                               istep1, my_task, iblk
            write (nu_diag,*) 'Global block:', this_block%block_id
            if (istop > 0 .and. jstop > 0) &
                 write(nu_diag,*) 'Global i and j:', &
                                  this_block%i_glob(istop), &
                                  this_block%j_glob(jstop) 
            call abort_ice ('ice: add_new_ice error')
         endif

      !-----------------------------------------------------------------
      ! Melt ice laterally.
      !-----------------------------------------------------------------
         call lateral_melt (nx_block, ny_block,     &
                            ilo, ihi, jlo, jhi,     &
                            dt,                     &
                            fresh     (:,:,  iblk), &
                            fsalt     (:,:,  iblk), &    
                            fhocn     (:,:,  iblk), &
                            rside     (:,:,  iblk), &
                            meltl     (:,:,  iblk), &
                            aicen     (:,:,:,iblk), &
                            vicen     (:,:,:,iblk), &
                            vsnon     (:,:,:,iblk), &
                            eicen     (:,:,:,iblk), &
                            esnon     (:,:,:,iblk) )

      !-----------------------------------------------------------------
      ! For the special case of a single category, adjust the area and
      ! volume (assuming that half the volume change decreases the
      ! thickness, and the other half decreases the area).  
      !-----------------------------------------------------------------

!echmod: test this
         if (ncat==1) &
             call reduce_area (nx_block, ny_block,     &
                               ilo, ihi, jlo, jhi,     &
                               tmask     (:,:,  iblk), &
                               aicen     (:,:,1,iblk), &
                               vicen     (:,:,1,iblk), &
                               aicen_init(:,:,1,iblk), &
                               vicen_init(:,:,1,iblk))

      !-----------------------------------------------------------------
      ! ITD cleanup: Rebin thickness categories if necessary, and remove
      !  categories with very small areas.
      !-----------------------------------------------------------------

         call cleanup_itd (nx_block,             ny_block,             &
                           ilo, ihi,             jlo, jhi,             &
                           dt,                                         &
                           aicen   (:,:,:,iblk), trcrn (:,:,:,:,iblk), &
                           vicen   (:,:,:,iblk), vsnon (:,:,  :,iblk), &
                           eicen   (:,:,:,iblk), esnon (:,:,  :,iblk), &
                           aice0   (:,:,  iblk), aice      (:,:,iblk), &
                           trcr_depend,                                &
                           fresh   (:,:,  iblk), fsalt     (:,:,iblk), &
                           fhocn   (:,:,  iblk),                       &
                           heat_capacity,        l_stop,               &
                           istop,                jstop)

         if (l_stop) then
            write (nu_diag,*) 'istep1, my_task, iblk =', &
                               istep1, my_task, iblk
            write (nu_diag,*) 'Global block:', this_block%block_id
            if (istop > 0 .and. jstop > 0) &
                 write(nu_diag,*) 'Global i and j:', &
                                  this_block%i_glob(istop), &
                                  this_block%j_glob(jstop) 
            call abort_ice ('ice: ITD cleanup error')
         endif

      enddo                     ! iblk

      !-------------------------------------------------------------------
      ! Ghost cell updates for state variables.
      !-------------------------------------------------------------------

      call ice_timer_start(timer_bound)
      call bound_state (aicen, trcrn, &
                        vicen, vsnon, &
                        eicen, esnon)
      call ice_timer_stop(timer_bound)

      do iblk = 1, nblocks

      !-----------------------------------------------------------------
      ! Aggregate the updated state variables (includes ghost cells). 
      !----------------------------------------------------------------- 
 
         call aggregate (nx_block,          ny_block,             &
                         aicen(:,:,:,iblk), trcrn(:,:,:,:,iblk),  &
                         vicen(:,:,:,iblk), vsnon(:,:,  :,iblk),  &
                         eicen(:,:,:,iblk), esnon(:,:,  :,iblk),  &
                         aice (:,:,  iblk), trcr (:,:,:,  iblk),  &
                         vice (:,:,  iblk), vsno (:,:,    iblk),  &
                         eice (:,:,  iblk), esno (:,:,    iblk),  &
                         aice0(:,:,  iblk), tmask(:,:,    iblk),  &
                         trcr_depend) 

      !-----------------------------------------------------------------
      ! Compute thermodynamic area and volume tendencies.
      !-----------------------------------------------------------------

         do j = 1, ny_block
         do i = 1, nx_block
            daidtt(i,j,iblk) = (aice(i,j,iblk) - daidtt(i,j,iblk)) / dt
            dvidtt(i,j,iblk) = (vice(i,j,iblk) - dvidtt(i,j,iblk)) / dt
         enddo
         enddo

      enddo                     ! iblk

      call ice_timer_stop(timer_thermo)  ! thermodynamics
      call ice_timer_stop(timer_column)  ! column physics

      end subroutine step_therm2

!=======================================================================
!BOP
!
! !ROUTINE: step_dynamics - step ice dynamics, transport, and ridging
!
! !DESCRIPTION:
!
! Run one time step of dynamics, horizontal transport, and ridging.
! NOTE: The evp and transport modules include boundary updates, so
!       they cannot be done inside a single block loop.  Ridging
!       and cleanup, on the other hand, are single-column operations. 
!       They are called with argument lists inside block loops
!       to increase modularity.
!
! !REVISION HISTORY:
!
! authors: William H. Lipscomb, LANL
!
! !INTERFACE:

      subroutine step_dynamics (dt, frocean, gfresh, gfsalt, gfhocn)
!
! !USES:
!
! !INPUT/OUTPUT PARAMETERS:
!
      real (kind=dbl_kind), intent(in) :: &
         dt      ! time step

      real (kind=real_kind), &
         dimension(:,:), &
         intent(in) :: &
         frocean   
      real (kind=real_kind), &
         dimension(:,:), &
         intent(inout) :: &
         gfresh, gfsalt, gfhocn 

!
!EOP
!
      type (block) :: &
         this_block      ! block information for current block

      integer (kind=int_kind) :: & 
         iblk        , & ! block index 
         ist,jst     , &
         i,j         , & ! horizontal indices
         ilo,ihi,jlo,jhi ! beginning and end of physical domain

      integer (kind=int_kind) :: &
         icells          ! number of cells with aicen > puny

      integer (kind=int_kind), dimension(nx_block*ny_block) :: &
         indxi, indxj    ! indirect indices for cells with aicen > puny

      logical (kind=log_kind) :: &
         l_stop          ! if true, abort model

      integer (kind=int_kind) :: &
         istop, jstop    ! indices of grid cell where model aborts

      integer (kind=int_kind) :: &
         narr            ! number of 2D state variable arrays in works array

      call init_history_dyn     ! initialize dynamic history variables

       !*** these fluxes are only accumulated within this subroutine
       !*** and they are used to update skin layer after 
       fhocn = 0.0
       fresh = 0.0
       fsalt = 0.0

      ! ------------------------------------
      ! Fill narr needed by transport_upwind
      ! ------------------------------------
      narr = 1 + ncat*(3+ntrcr)

      !-----------------------------------------------------------------
      ! Elastic-viscous-plastic ice dynamics
      !-----------------------------------------------------------------
      call evp (dt)

      !-----------------------------------------------------------------
      ! Horizontal ice transport
      !-----------------------------------------------------------------

      if (advection == 'upwind') then
         call transport_upwind (dt, narr)    ! upwind
      else
         call transport_remap (dt)     ! incremental remapping
      endif

!#ifdef DO_RIDGING
      !-----------------------------------------------------------------
      ! Ridging
      !-----------------------------------------------------------------

      call ice_timer_start(timer_column)
      call ice_timer_start(timer_ridge)

      l_stop = .false.

      do iblk = 1, nblocks
         this_block = get_block(blocks_ice(iblk), iblk)
         ilo = this_block%ilo
         ihi = this_block%ihi
         jlo = this_block%jlo
         jhi = this_block%jhi

      !-----------------------------------------------------------------
      ! Identify ice-ocean cells.
      ! Note:  We can not define icells here using aice>puny because
      !        aice has not yet been updated since the transport (and
      !        it may be out of whack, which the ridging helps fix).-ECH
      !-----------------------------------------------------------------
           
         icells = 0
         do j = jlo, jhi
         do i = ilo, ihi
!#ifdef 1
!            if (tmask(i,j,iblk) .and. frocean(i-nghost,j-nghost) > 1.e-6) then
!#else
            if (tmask(i,j,iblk)) then
!#endif
               icells = icells + 1
               indxi(icells) = i
               indxj(icells) = j
            endif
         enddo               ! i
         enddo               ! j


         if (icells > 0) then

         call ridge_ice (nx_block,             ny_block,                 &
                         dt,                   icells,                   &
                         indxi,                indxj,                    &
!!                         Delt    (:,:,  iblk), divu      (:,:,  iblk), &
                         rdg_conv(:,:,  iblk), rdg_shear (:,:,  iblk),   &
                         aicen   (:,:,:,iblk), trcrn     (:,:,:,:,iblk), &
                         vicen   (:,:,:,iblk), vsnon     (:,:,:,iblk),   &
                         eicen   (:,:,:,iblk), esnon     (:,:,:,iblk),   &
                         aice0   (:,:,  iblk),                           &
                         trcr_depend,          l_stop,                   &
                         istop,                jstop,                    &   
                         dardg1dt(:,:,iblk),   dardg2dt  (:,:,iblk),     &
                         dvirdgdt(:,:,iblk),   opening   (:,:,iblk),     &
!#ifdef 1
!                         gfresh   (:,:),  gfhocn     (:,:))
!#else
                         fresh   (:,:,iblk),   fhocn     (:,:,iblk))
!#endif

         if (l_stop) then
            write (nu_diag,*) 'istep1, my_task, iblk =', &
                               istep1, my_task, iblk
            write (nu_diag,*) 'Global block:', this_block%block_id
            if (istop > 0 .and. jstop > 0) then
                 write(nu_diag,*) 'Local i and j:', &
                                  istop, &
                                  jstop 
                 write(nu_diag,*) 'Global i and j:', &
                                  this_block%i_glob(istop), &
                                  this_block%j_glob(jstop) 
            endif
            call abort_ice ('ice: Ridging error')
         endif

         endif

      enddo                     ! iblk


      call ice_timer_stop(timer_ridge)
!#endif

      do iblk = 1, nblocks
         this_block = get_block(blocks_ice(iblk), iblk)
         ilo = this_block%ilo
         ihi = this_block%ihi
         jlo = this_block%jlo
         jhi = this_block%jhi

      !-----------------------------------------------------------------
      ! ITD cleanup: Rebin thickness categories if necessary, and remove
      !  categories with very small areas.
      !-----------------------------------------------------------------

         call cleanup_itd (nx_block,             ny_block,             &
                           ilo, ihi,             jlo, jhi,             &
                           dt,                                         &
                           aicen   (:,:,:,iblk), trcrn (:,:,:,:,iblk), &
                           vicen   (:,:,:,iblk), vsnon (:,:,  :,iblk), &
                           eicen   (:,:,:,iblk), esnon (:,:,  :,iblk), &
                           aice0   (:,:,  iblk), aice      (:,:,iblk), &
                           trcr_depend,                                &
!#ifdef 1
                           fresh   (:,:,  iblk), fsalt     (:,:,iblk), &
                           fhocn   (:,:,  iblk),                       &
!#else
!                           gfresh   (:,:), gfsalt     (:,:),           &
!                           gfhocn   (:,:),                             &
!#endif
                           heat_capacity,        l_stop,               &
                           istop, jstop, limit_aice_in=.true. &
                           ) !, together = .true.)

         if (l_stop) then
            write (nu_diag,*) 'istep1, my_task, iblk =', &
                               istep1, my_task, iblk
            write (nu_diag,*) 'Global block:', this_block%block_id
            if (istop > 0 .and. jstop > 0) then
                 write(nu_diag,*) 'Local i and j:', &
                                  istop, &
                                  jstop 
                 write(nu_diag,*) 'Global i and j:', &
                                  this_block%i_glob(istop), &
                                  this_block%j_glob(jstop) 
            endif 
            call abort_ice ('ice: ITD cleanup error')
         endif

      enddo                     ! iblk
      !-------------------------------------------------------------------
      ! Ghost cell updates for state variables.
      !-------------------------------------------------------------------

      call ice_timer_start(timer_bound)
      call bound_state (aicen, trcrn, &
                        vicen, vsnon, &
                        eicen, esnon)
      call ice_timer_stop(timer_bound)


      do iblk = 1, nblocks

      !-----------------------------------------------------------------
      ! Aggregate the updated state variables (includes ghost cells). 
      !----------------------------------------------------------------- 
 
         call aggregate (nx_block,          ny_block,             &
                         aicen(:,:,:,iblk), trcrn(:,:,:,:,iblk),  &
                         vicen(:,:,:,iblk), vsnon(:,:,  :,iblk),  &
                         eicen(:,:,:,iblk), esnon(:,:,  :,iblk),  &
                         aice (:,:,  iblk), trcr (:,:,:,  iblk),  &
                         vice (:,:,  iblk), vsno (:,:,    iblk),  &
                         eice (:,:,  iblk), esno (:,:,    iblk),  &
                         aice0(:,:,  iblk), tmask(:,:,    iblk),  &
                         trcr_depend) 
      enddo


      do iblk = 1, nblocks
      !-----------------------------------------------------------------
      ! Compute dynamic area and volume tendencies.
      !-----------------------------------------------------------------

         this_block = get_block(blocks_ice(iblk),iblk)         
         ilo = this_block%ilo
         ihi = this_block%ihi
         jlo = this_block%jlo
         jhi = this_block%jhi

         do j = jlo,jhi
         do i = ilo,ihi
            dvidtd(i,j,iblk) = (vice(i,j,iblk) - dvidtd(i,j,iblk)) /dt
            daidtd(i,j,iblk) = (aice(i,j,iblk) - daidtd(i,j,iblk)) /dt
            if (tmask(i,j,iblk)) then
               ist = i-nghost
               jst = j-nghost
               gfresh(ist,jst) = gfresh(ist,jst) + fresh(i,j,iblk)
               gfsalt(ist,jst) = gfsalt(ist,jst) + fsalt(i,j,iblk)
               gfhocn(ist,jst) = gfhocn(ist,jst) + fhocn(i,j,iblk)
            endif
         enddo
         enddo

      enddo

      call ice_timer_stop(timer_column)

      end subroutine step_dynamics

      subroutine cleanup_itd_before_dynamics

       integer (kind=int_kind) :: &
         iblk           , & ! block index
         ilo,ihi,jlo,jhi, & ! beginning and end of physical domain
         i, j, i1, j1, k, n

       type (block) :: &
         this_block           ! block information for current block

      logical (kind=log_kind) :: &
         l_stop          ! if true, abort model

      integer (kind=int_kind) :: &
         istop, jstop    ! indices of grid cell where model aborts

      real (kind=dbl_kind), dimension(nx_block,ny_block,max_blocks) :: &
         dumfresh, dumfsalt, dumfhocn          

         l_stop = .false.

        do iblk = 1, nblocks  
           this_block = get_block(blocks_ice(iblk),iblk)
           ilo = this_block%ilo
           ihi = this_block%ihi
           jlo = this_block%jlo
           jhi = this_block%jhi

           call cleanup_itd (nx_block,             ny_block,           &
                           ilo, ihi,             jlo, jhi,             &
                           dt,                                         &
                           aicen   (:,:,:,iblk), trcrn (:,:,:,:,iblk), &
                           vicen   (:,:,:,iblk), vsnon (:,:,  :,iblk), &
                           eicen   (:,:,:,iblk), esnon (:,:,  :,iblk), &
                           aice0   (:,:,  iblk), aice      (:,:,iblk), &
                           trcr_depend,                                &
                           dumfresh(:,:,  iblk),   dumfsalt(:,:,iblk), &
                           dumfhocn(:,:,  iblk),                       &
                           heat_capacity,         l_stop,              &
                           istop,                 jstop,               &
                           limit_aice_in=.true.)

           if (l_stop) then
              write (*,*) 'Global block:', this_block%block_id
              if (istop > 0 .and. jstop > 0) &
                 write(*,*) 'Global i and j:', &
                                  this_block%i_glob(istop), &
                                  this_block%j_glob(jstop) 
              call abort_ice ('ice: ITD cleanup error')
          endif
       enddo

       call bound_state (aicen, trcrn, &
                         vicen, vsnon, &
                         eicen, esnon)

      end subroutine cleanup_itd_before_dynamics

      subroutine incremental_update_skin(tw, hw, sw, dhw, dti, swcap)

      use ice_boundary
      use ice_domain
      use ice_constants
      use ice_grid,                only: tmask
      use ice_flux,                only: fhocn, fsalt, fresh

      real (kind=real_kind), &
         dimension(:,:), intent(inout) :: &
         tw, hw, sw, dhw  

      real (kind=dbl_kind),  intent(in) :: &
         dti

      real (kind=real_kind),  intent(in) :: &
         swcap

!
!EOP
!
       integer (kind=int_kind) :: &
         iblk           , & ! block index
         ilo,ihi,jlo,jhi, & ! beginning and end of physical domain
         i, j, k, n, ist, jst
       type (block) :: &
         this_block           ! block information for current block
      real (kind=real_kind) :: &
         sws, freshdt

       do iblk = 1, nblocks
           this_block = get_block(blocks_ice(iblk),iblk)
           ilo = this_block%ilo
           ihi = this_block%ihi
           jlo = this_block%jlo
           jhi = this_block%jhi

           do j = jlo, jhi
           do i = ilo, ihi
              ist = i-nghost
              jst = j-nghost
              if(tmask(i,j,iblk)) then
                 sws = sw(ist,jst) * hw(ist, jst)
                 tw(ist,jst) = tw(ist,jst) + dti * &
                                fhocn(i,j,iblk) &
                              / (swcap * hw(ist, jst))
                 freshdt      = dti * fresh(i,j,iblk)   
                 hw(ist,jst)  = hw(ist,jst) + freshdt
                 dhw(ist,jst) = freshdt
                 sw(ist,jst)  = (sws + dti * &
                 !*** multiply by 1000 to account for g->kg conversion
                                1.e3 * fsalt(i,j,iblk)) / hw(ist,jst)
              endif
           enddo
           enddo  
       enddo
         
      end subroutine incremental_update_skin 

!=======================================================================
!BOP
!
! !ROUTINE: step_radiation
!
! !DESCRIPTION:
!
! Computes radiation fields
!
! !REVISION HISTORY:
!
! authors: William H. Lipscomb, LANL
!          David Bailey, NCAR
!          Elizabeth C. Hunke, LANL
!
! !INTERFACE:

      subroutine step_radiation (dt)

! !INPUT/OUTPUT PARAMETERS:
!
      real (kind=dbl_kind), intent(in) :: &
         dt      ! time step
!
!EOP
!
      integer (kind=int_kind) :: &
         i, j, ij    , & ! horizontal indices
         iblk        , & ! block index
         ilo,ihi,jlo,jhi, & ! beginning and end of physical domain
         n           , & ! thickness category index
         il1, il2    , & ! ice layer indices for eice
         sl1, sl2        ! snow layer indices for esno

      integer (kind=int_kind) :: &
         icells          ! number of cells with aicen > puny

      integer (kind=int_kind), dimension(nx_block*ny_block) :: &
         indxi, indxj    ! indirect indices for cells with aicen > puny

      ! snow variables for Delta-Eddington shortwave
      real (kind=dbl_kind), dimension (nx_block,ny_block) :: &
         fsn             ! snow horizontal fraction

      real (kind=dbl_kind), dimension (nx_block,ny_block,nslyr) :: &
         rhosnwn     , & ! snow density (kg/m3)
         rsnwn           ! snow grain radius (micrometers)

      ! pond variables for Delta-Eddington shortwave
      real (kind=dbl_kind), dimension (nx_block,ny_block) :: &
         fpn         , & ! pond fraction
         hpn             ! pond depth (m)

      logical, dimension (nx_block,ny_block) :: &
          observe
      real (kind=dbl_kind), dimension (nx_block,ny_block) :: &
         druvr,    dfuvr,    &
         drpar,    dfpar

      real (kind=dbl_kind), dimension (nx_block,ny_block) ::  & 
         druvrthru,    dfuvrthru,    &
         drparthru,    dfparthru

      type (block) :: &
         this_block      ! block information for current block

      call ice_timer_start(timer_column)  ! column physics
      call ice_timer_start(timer_thermo)  ! thermodynamics
      call ice_timer_start(timer_sw)      ! shortwave

         observe(:,:) = .true.     
         druvr(:,:) = c0
         dfuvr(:,:) = c0
         drpar(:,:) = c0
         dfpar(:,:) = c0

      if (calc_Tsfc) then

      do iblk = 1, nblocks
         this_block = get_block(blocks_ice(iblk),iblk)         
         ilo = this_block%ilo
         ihi = this_block%ihi
         jlo = this_block%jlo
         jhi = this_block%jhi

      !-----------------------------------------------------------------
      ! Compute cosine of solar zenith angle.
      ! This is used by the delta-Eddington shortwave module.
      ! For basic shortwave, simply set coszen to a constant between 0 and 1.
      !-----------------------------------------------------------------

         if (trim(shortwave) == 'dEdd') then ! delta Eddington

            ! identify ice-ocean cells
            icells = 0
            do j = 1, ny_block
            do i = 1, nx_block
               if (tmask(i,j,iblk)) then
                  icells = icells + 1
                  indxi(icells) = i
                  indxj(icells) = j
               endif
            enddo               ! i
            enddo               ! j

            call compute_coszen (nx_block,         ny_block,       &
                                 icells,                           &
                                 indxi,            indxj,          &
                                 tlat  (:,:,iblk), tlon(:,:,iblk), &
                                 coszen(:,:,iblk), dt)

         else                     ! basic (ccsm3) shortwave
            coszen(:,:,iblk) = p5 ! sun above the horizon
         endif

         do n = 1, ncat

      !-----------------------------------------------------------------
      ! Identify cells with nonzero ice area
      !-----------------------------------------------------------------
           
            icells = 0
            do j = jlo, jhi
            do i = ilo, ihi
               if (aicen(i,j,n,iblk) > puny) then
                  icells = icells + 1
                  indxi(icells) = i
                  indxj(icells) = j
               endif
            enddo               ! i
            enddo               ! j

      !-----------------------------------------------------------------
      ! Solar radiation: albedo and absorbed shortwave
      !-----------------------------------------------------------------

            il1 = ilyr1(n)
            il2 = ilyrn(n)
            sl1 = slyr1(n)
            sl2 = slyrn(n)

            if (trim(shortwave) == 'dEdd') then   ! delta Eddington

      ! note that rhoswn, rsnw, fp, hp and Sswabs ARE NOT dimensioned with ncat
      ! BPB 19 Dec 2006

               ! set snow properties
               call shortwave_dEdd_set_snow(nx_block, ny_block,        &
                              icells,                                  &
                              indxi,               indxj,              &
                              aicen(:,:,n,iblk),   vsnon(:,:,n,iblk),  &
                              trcrn(:,:,nt_Tsfc,n,iblk), fsn,          &
                              rhosnwn,             rsnwn)

               if (.not. tr_pond) then
                   ! set pond properties
                   call shortwave_dEdd_set_pond(nx_block, ny_block,     &
                              icells,                                   &
                              indxi,               indxj,               &
                              aicen(:,:,n,iblk),                        &
                              trcrn(:,:,nt_Tsfc,n,iblk),                &
                              fsn,                 fpn,                 &
                              hpn)
               else
                  fpn(:,:) = apondn(:,:,n,iblk)
                  hpn(:,:) = hpondn(:,:,n,iblk)
               endif

               call shortwave_dEdd(nx_block,     ny_block,            &
                              icells,                                 &
                              indxi,             indxj,               &
                              coszen(:,:, iblk),                      &
                              aicen(:,:,n,iblk), vicen(:,:,n,iblk),   &
                              vsnon(:,:,n,iblk), fsn,                 &
                              rhosnwn,           rsnwn,               &
                              fpn,               hpn,                 &
                              observe,               &
                              druvr,    dfuvr,       &
                              drpar,    dfpar,       &
                              swvdr(:,:,  iblk), swvdf(:,:,  iblk),   &
                              swidr(:,:,  iblk), swidf(:,:,  iblk),   &
                              alvdrn(:,:,n,iblk),alvdfn(:,:,n,iblk),  &
                              alidrn(:,:,n,iblk),alidfn(:,:,n,iblk),  &
                              fswsfcn(:,:,n,iblk),fswintn(:,:,n,iblk),&
                              fswthrun(:,:,n,iblk),                   &
                              Sswabsn(:,:,sl1:sl2,iblk),              &
                              Iswabsn(:,:,il1:il2,iblk), &
                              druvrthru, dfuvrthru,  &
                              drparthru, dfparthru,  &
                              albicen(:,:,n,iblk),      &
                              albsnon(:,:,n,iblk),albpndn(:,:,n,iblk))

            else  ! .not. dEdd

               Sswabsn(:,:,sl1:sl2,iblk) = c0

            endif  ! dEdd
         enddo                  ! ncat
      enddo                     ! nblocks

      else    ! .not. calc_Tsfc

         ! Initialize for safety
         do iblk = 1, nblocks
         do n = 1, ncat
         do j = 1, ny_block
         do i = 1, nx_block
            alvdrn(i,j,n,iblk) = c0
            alidrn(i,j,n,iblk) = c0
            alvdfn(i,j,n,iblk) = c0
            alidfn(i,j,n,iblk) = c0
            fswsfcn(i,j,n,iblk) = c0
            fswintn(i,j,n,iblk) = c0
            fswthrun(i,j,n,iblk) = c0
         enddo   ! i
         enddo   ! j
         enddo   ! ncat
            Iswabsn(:,:,:,iblk) = c0
            Sswabsn(:,:,:,iblk) = c0
         enddo   ! iblk

      endif    ! calc_Tsfc

      call ice_timer_stop(timer_sw)     ! shortwave
      call ice_timer_stop(timer_thermo) ! thermodynamics
      call ice_timer_stop(timer_column) ! column physics

      end subroutine step_radiation

!=======================================================================

      end module ice_step_mod

!=======================================================================
