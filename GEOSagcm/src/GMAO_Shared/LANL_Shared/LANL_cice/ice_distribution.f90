












!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
!BOP
! !MODULE: ice_distribution

 module ice_distribution

!
! !DESCRIPTION:
!  This module provides data types and routines for distributing
!  blocks across processors.
!
! !REVISION HISTORY:
!  SVN:$Id$
!
! author: Phil Jones, LANL
! Oct. 2004: Adapted from POP by William H. Lipscomb, LANL
! Jan. 2008: Elizabeth Hunke updated to new POP infrastructure
!
! !USES:

   use ice_kinds_mod
   use ice_communicate
   use ice_blocks
   use ice_exit
   use ice_fileunits, only: nu_diag
   use ice_spacecurve

   implicit none
   private
   save

! !PUBLIC TYPES:

   type, public :: distrb  ! distribution data type
      integer (int_kind) :: &
         nprocs            ,&! number of processors in this dist
         communicator      ,&! communicator to use in this dist
         numLocalBlocks      ! number of blocks distributed to this
                             !   local processor

      integer (int_kind), dimension(:), pointer :: &
         blockLocation     ,&! processor location for all blocks
         blockLocalID      ,&! local  block id for all blocks
         blockGlobalID       ! global block id for each local block
   end type

! !PUBLIC MEMBER FUNCTIONS:

   public :: create_distribution, &
             ice_distributionGet,         &
             ice_distributionGetBlockLoc, &
             ice_distributionGetBlockID, &
             create_local_block_ids

! !PUBLIC DATA MEMBERS:

   character (char_len), public :: &
       processor_shape       ! 'square-pop' (approx) POP default config
                             ! 'square-ice' like square-pop but better for ice
                             ! 'slenderX1' (NPX x 1)
                             ! 'slenderX2' (NPX x 2)

!EOP
!BOC
!EOC
!***********************************************************************

 contains

!***********************************************************************
!BOP
! !IROUTINE: create_distribution
! !INTERFACE:

 function create_distribution(dist_type, nprocs, work_per_block)

! !DESCRIPTION:
!  This routine determines the distribution of blocks across processors
!  by call the appropriate subroutine based on distribution type
!  requested.  Currently three distributions are supported:
!  2-d Cartesian distribution (cartesian), a load-balanced
!  distribution using a rake algorithm based on an input amount of work 
!  per block, and a space-filling-curve algorithm.
!
! !REVISION HISTORY:
!  same as module

! !INPUT PARAMETERS:

   character (*), intent(in) :: &
      dist_type             ! method for distributing blocks
                            !  either cartesian or rake

   integer (int_kind), intent(in) :: &
      nprocs                ! number of processors in this distribution

   integer (int_kind), dimension(:), intent(in) :: &
      work_per_block        ! amount of work per block

! !OUTPUT PARAMETERS:

   type (distrb) :: &
      create_distribution   ! resulting structure describing
                            !  distribution of blocks

!EOP
!BOC
!----------------------------------------------------------------------
!
!  select the appropriate distribution type
!
!----------------------------------------------------------------------

   select case (trim(dist_type))

   case('cartesian')

      create_distribution = create_distrb_cart(nprocs, work_per_block)

   case('rake')

      create_distribution = create_distrb_rake(nprocs, work_per_block)

   case('spacecurve')

      create_distribution = create_distrb_spacecurve(nprocs, &
                                                   work_per_block)

   case default

      call abort_ice('ice distribution: unknown distribution type')

   end select

!-----------------------------------------------------------------------
!EOC

 end function create_distribution

!***********************************************************************
!BOP
! !IROUTINE: create_local_block_ids
! !INTERFACE:

 subroutine create_local_block_ids(block_ids, distribution)

! !DESCRIPTION:
!  This routine determines which blocks in an input distribution are
!  located on the local processor and creates an array of block ids
!  for all local blocks.
!
! !REVISION HISTORY:
!  same as module

! !INPUT PARAMETERS:

   type (distrb), intent(in) :: &
      distribution           ! input distribution for which local
                             !  blocks required

! !OUTPUT PARAMETERS:

   integer (int_kind), dimension(:), pointer :: &
      block_ids              ! array of block ids for every block
                             ! that resides on the local processor
!EOP
!BOC
!-----------------------------------------------------------------------
!
!  local variables
!
!-----------------------------------------------------------------------

   integer (int_kind) :: &
      n, bid, bcount        ! dummy counters

   logical (log_kind) :: dbug

!-----------------------------------------------------------------------
!
!  first determine number of local blocks to allocate array
!
!-----------------------------------------------------------------------

   bcount = 0
   do n=1,size(distribution%blockLocation)
      if (distribution%blockLocation(n) == my_task+1) bcount = bcount + 1
   end do


   if (bcount > 0) allocate(block_ids(bcount))

!-----------------------------------------------------------------------
!
!  now fill array with proper block ids
!
!-----------------------------------------------------------------------

   dbug = .true.
!   dbug = .false.
   if (bcount > 0) then
      do n=1,size(distribution%blockLocation)
         if (distribution%blockLocation(n) == my_task+1) then
            block_ids(distribution%blockLocalID(n)) = n

            if (dbug) then
            write(nu_diag,*) 'block id, proc, local_block: ', &
                             block_ids(distribution%blockLocalID(n)), &
                             distribution%blockLocation(n), &
                             distribution%blockLocalID(n)
            endif
         endif
      end do
   endif

!EOC

 end subroutine create_local_block_ids

!***********************************************************************
!BOP
! !IROUTINE: proc_decomposition
! !INTERFACE:

 subroutine proc_decomposition(nprocs, nprocs_x, nprocs_y)

! !DESCRIPTION:
!  This subroutine attempts to find an optimal (nearly square)
!  2d processor decomposition for a given number of processors.
!
! !REVISION HISTORY:
!  same as module
!
! !USES:

   use ice_domain_size

! !INPUT PARAMETERS:

   integer (int_kind), intent(in) :: &
      nprocs                       ! total number or processors

! !OUTPUT PARAMETERS:

   integer (int_kind), intent(out) :: &
      nprocs_x, nprocs_y           ! number of procs in each dimension

!EOP
!BOC
!----------------------------------------------------------------------
!
!  local variables
!
!----------------------------------------------------------------------

   integer (int_kind) :: &
      iguess, jguess               ! guesses for nproc_x,y

   real (real_kind) :: &
      square                       ! square root of nprocs

!----------------------------------------------------------------------
!
!  start with an initial guess
!
!----------------------------------------------------------------------

   square = sqrt(real(nprocs,kind=real_kind))
   nprocs_x = 0
   nprocs_y = 0

   if (processor_shape == 'square-pop') then ! make as square as possible
      iguess = nint(square)
      jguess = nprocs/iguess
   elseif (processor_shape == 'square_ice') then ! better for bipolar ice
      jguess = nint(square)
      iguess = nprocs/jguess
   elseif (processor_shape == 'slenderX1') then ! 1 proc in y direction
      jguess = 1
      iguess = nprocs/jguess
   else                                  ! 2 processors in y direction
      jguess = min(2, nprocs)
      iguess = nprocs/jguess
   endif

!----------------------------------------------------------------------
!
!  try various decompositions to find the best
!
!----------------------------------------------------------------------

   proc_loop: do
   if (processor_shape == 'square-pop') then
      jguess = nprocs/iguess
   else
      iguess = nprocs/jguess
   endif

      if (iguess*jguess == nprocs) then ! valid decomp

         !*** if the blocks can be evenly distributed, it is a
         !*** good decomposition
         if (mod(nblocks_x,iguess) == 0 .and. &
             mod(nblocks_y,jguess) == 0) then
            nprocs_x = iguess
            nprocs_y = jguess
            exit proc_loop

         !*** if the blocks can be evenly distributed in a
         !*** transposed direction, it is a good decomposition
         else if (mod(nblocks_x,jguess) == 0 .and. &
                mod(nblocks_y,iguess) == 0) then
            nprocs_x = jguess
            nprocs_y = iguess
            exit proc_loop

         !*** A valid decomposition, but keep searching for
         !***  a better one
         else
            if (nprocs_x == 0) then
               nprocs_x = iguess
               nprocs_y = jguess
            endif
            if (processor_shape == 'square-pop') then
               iguess = iguess - 1
               if (iguess == 0) then
                  exit proc_loop
               else
                  cycle proc_loop
               endif
            else
               jguess = jguess - 1
               if (jguess == 0) then
                  exit proc_loop
               else
                  cycle proc_loop
               endif
            endif
         endif

      else ! invalid decomp - keep trying

         if (processor_shape == 'square-pop') then
            iguess = iguess - 1
            if (iguess == 0) then
               exit proc_loop
            else
               cycle proc_loop
            endif
         else
            jguess = jguess - 1
            if (jguess == 0) then
               exit proc_loop
            else
               cycle proc_loop
            endif
         endif
      endif

   end do proc_loop

   if (nprocs_x == 0) then
      call abort_ice('ice: Unable to find 2d processor config')
   endif

   if (my_task == master_task) then
     write(nu_diag,'(a23,i4,a3,i4)') '  Processors (X x Y) = ', &
                                        nprocs_x,' x ',nprocs_y
   endif

!----------------------------------------------------------------------
!EOC

 end subroutine proc_decomposition

!**********************************************************************
!BOP
! !IROUTINE: ice_distributionDestroy
! !INTERFACE:

 subroutine ice_distributionDestroy(distribution)

! !DESCRIPTION:
!  This routine destroys a defined distribution by deallocating
!  all memory associated with the distribution.
!
! !REVISION HISTORY:
!  same as module

! !INPUT/OUTPUT PARAMETERS:

   type (distrb), intent(inout) :: &
      distribution          ! distribution to destroy

! !OUTPUT PARAMETERS:

!EOP
!BOC
!----------------------------------------------------------------------
!
!  local variables
!
!----------------------------------------------------------------------

   integer (int_kind) :: istat  ! status flag for deallocate

!----------------------------------------------------------------------
!
!  reset scalars
!
!----------------------------------------------------------------------

   distribution%nprocs       = 0
   distribution%communicator   = 0
   distribution%numLocalBlocks = 0

!----------------------------------------------------------------------
!
!  deallocate arrays
!
!----------------------------------------------------------------------

   deallocate(distribution%blockLocation, stat=istat)
   deallocate(distribution%blockLocalID , stat=istat)
   deallocate(distribution%blockGlobalID, stat=istat)

!-----------------------------------------------------------------------
!EOC

 end subroutine ice_distributionDestroy

!***********************************************************************
!BOP
! !IROUTINE: ice_distributionGet
! !INTERFACE:

 subroutine ice_distributionGet(distribution,&
                            nprocs, communicator, numLocalBlocks, &
                            blockLocation, blockLocalID, blockGlobalID)


! !DESCRIPTION:
!  This routine extracts information from a distribution.
!
! !REVISION HISTORY:
!  same as module

! !INPUT PARAMETERS:

   type (distrb), intent(in) :: &
      distribution           ! input distribution for which information
                             !  is requested

! !OUTPUT PARAMETERS:

      integer (int_kind), intent(out), optional ::   &
         nprocs          ,&! number of processors in this dist
         communicator      ,&! communicator to use in this dist
         numLocalBlocks      ! number of blocks distributed to this
                             !   local processor

      integer (int_kind), dimension(:), pointer, optional :: &
         blockLocation     ,&! processor location for all blocks
         blockLocalID      ,&! local  block id for all blocks
         blockGlobalID       ! global block id for each local block

!EOP
!BOC
!-----------------------------------------------------------------------
!
!  depending on which optional arguments are present, extract the
!  requested info
!
!-----------------------------------------------------------------------

   if (present(nprocs))       nprocs       = distribution%nprocs
   if (present(communicator))   communicator   = distribution%communicator
   if (present(numLocalBlocks)) numLocalBlocks = distribution%numLocalBlocks

   if (present(blockLocation)) then
      if (associated(distribution%blockLocation)) then
         blockLocation => distribution%blockLocation
      else
        call abort_ice( &
            'ice_distributionGet: blockLocation not allocated')
         return
      endif
   endif

   if (present(blockLocalID)) then
      if (associated(distribution%blockLocalID)) then
         blockLocalID = distribution%blockLocalID
      else
        call abort_ice( &
            'ice_distributionGet: blockLocalID not allocated')
         return
      endif
   endif

   if (present(blockGlobalID)) then
      if (associated(distribution%blockGlobalID)) then
         blockGlobalID = distribution%blockGlobalID
      else
        call abort_ice( &
            'ice_distributionGet: blockGlobalID not allocated')
         return
      endif
   endif

!-----------------------------------------------------------------------
!EOC

 end subroutine ice_distributionGet

!***********************************************************************
!BOP
! !IROUTINE: ice_distributionGetBlockLoc
! !INTERFACE:

 subroutine ice_distributionGetBlockLoc(distribution, blockID, &
                                        processor, localID)


! !DESCRIPTION:
!  Given a distribution of blocks and a global block ID, return
!  the processor and local index for the block.  A zero for both
!  is returned in the case that the block has been eliminated from
!  the distribution (i.e. has no active points).
!
! !REVISION HISTORY:
!  same as module

! !INPUT PARAMETERS:

   type (distrb), intent(in) :: &
      distribution           ! input distribution for which information
                             !  is requested

   integer (int_kind), intent(in) :: &
      blockID                ! global block id for which location requested

! !OUTPUT PARAMETERS:

   integer (int_kind), intent(out) ::  &
      processor,            &! processor on which block resides
      localID                ! local index for this block on this proc

!EOP
!BOC
!-----------------------------------------------------------------------
!
!  check for valid blockID
!
!-----------------------------------------------------------------------

   if (blockID < 0 .or. blockID > nblocks_tot) then
     call abort_ice( &
         'ice_distributionGetBlockLoc: invalid block id')
      return
   endif

!-----------------------------------------------------------------------
!
!  extract the location from the distribution data structure
!
!-----------------------------------------------------------------------

   processor = distribution%blockLocation(blockID)
   localID   = distribution%blockLocalID (blockID)

!-----------------------------------------------------------------------
!EOC

 end subroutine ice_distributionGetBlockLoc

!***********************************************************************
!BOP
! !IROUTINE: ice_distributionGetBlockID
! !INTERFACE:

 subroutine ice_distributionGetBlockID(distribution, localID, &
                                       blockID)


! !DESCRIPTION:
!  Given a distribution of blocks and a local block index, return
!  the global block id for the block.
!
! !REVISION HISTORY:
!  same as module

! !INPUT PARAMETERS:

   type (distrb), intent(in) :: &
      distribution           ! input distribution for which information
                             !  is requested

   integer (int_kind), intent(in) ::  &
      localID                ! local index for this block on this proc

! !OUTPUT PARAMETERS:

   integer (int_kind), intent(out) :: &
      blockID                ! global block id for this local block

!EOP
!BOC
!-----------------------------------------------------------------------
!
!  check for valid localID
!
!-----------------------------------------------------------------------

   if (localID < 0 .or. localID > distribution%numLocalBlocks) then
     call abort_ice( &
         'ice_distributionGetBlockID: invalid local id')
      return
   endif

!-----------------------------------------------------------------------
!
!  extract the global ID from the distribution data structure
!
!-----------------------------------------------------------------------

   blockID   = distribution%blockGlobalID (localID)

!-----------------------------------------------------------------------
!EOC

 end subroutine ice_distributionGetBlockID

!***********************************************************************
!BOP
! !IROUTINE: create_distrb_cart
! !INTERFACE:

 function create_distrb_cart(nprocs, workPerBlock) result(newDistrb)

! !DESCRIPTION:
!  This function creates a distribution of blocks across processors
!  using a 2-d Cartesian distribution.
!
! !REVISION HISTORY:
!  same as module

! !INPUT PARAMETERS:

   integer (int_kind), intent(in) :: &
      nprocs            ! number of processors in this distribution

   integer (int_kind), dimension(:), intent(in) :: &
      workPerBlock        ! amount of work per block

! !OUTPUT PARAMETERS:

   type (distrb) :: &
      newDistrb           ! resulting structure describing Cartesian
                          !  distribution of blocks

!EOP
!BOC
!----------------------------------------------------------------------
!
!  local variables
!
!----------------------------------------------------------------------

   integer (int_kind) :: &
      i, j,                  &! dummy loop indices
      istat,                 &! status flag for allocation
      iblock, jblock,        &!
      is, ie, js, je,        &! start, end block indices for each proc
      processor,             &! processor position in cartesian decomp
      globalID,              &! global block ID
      localID,               &! block location on this processor
      nprocsX,             &! num of procs in x for global domain
      nprocsY,             &! num of procs in y for global domain
      numBlocksXPerProc,     &! num of blocks per processor in x
      numBlocksYPerProc       ! num of blocks per processor in y

!----------------------------------------------------------------------
!
!  create communicator for this distribution
!
!----------------------------------------------------------------------

   call create_communicator(newDistrb%communicator, nprocs)

!----------------------------------------------------------------------
!
!  try to find best processor arrangement
!
!----------------------------------------------------------------------

   newDistrb%nprocs = nprocs

   call proc_decomposition(nprocs, nprocsX, nprocsY)
                                  

!----------------------------------------------------------------------
!
!  allocate space for decomposition
!
!----------------------------------------------------------------------

   allocate (newDistrb%blockLocation(nblocks_tot), &
             newDistrb%blockLocalID (nblocks_tot), stat=istat)

!----------------------------------------------------------------------
!
!  distribute blocks linearly across processors in each direction
!
!----------------------------------------------------------------------

   numBlocksXPerProc = (nblocks_x-1)/nprocsX + 1
   numBlocksYPerProc = (nblocks_y-1)/nprocsY + 1

   do j=1,nprocsY
   do i=1,nprocsX
      processor = (j-1)*nprocsX + i    ! number the processors 
                                         ! left to right, bot to top

      is = (i-1)*numBlocksXPerProc + 1   ! starting block in i
      ie =  i   *numBlocksXPerProc       ! ending   block in i
      if (ie > nblocks_x) ie = nblocks_x
      js = (j-1)*numBlocksYPerProc + 1   ! starting block in j
      je =  j   *numBlocksYPerProc       ! ending   block in j
      if (je > nblocks_y) je = nblocks_y

      localID        = 0  ! initialize counter for local index
      do jblock = js,je
      do iblock = is,ie
         globalID = (jblock - 1)*nblocks_x + iblock
         if (workPerBlock(globalID) /= 0) then
            localID = localID + 1
            newDistrb%blockLocation(globalID) = processor
            newDistrb%blockLocalID (globalID) = localID
         else  ! no work - eliminate block from distribution
            newDistrb%blockLocation(globalID) = 0
            newDistrb%blockLocalID (globalID) = 0
         endif
      end do
      end do

      ! if this is the local processor, set number of local blocks
      if (my_task == processor - 1) then
         newDistrb%numLocalBlocks = localID
      endif

   end do
   end do

!----------------------------------------------------------------------
!
!  now store the local info
!
!----------------------------------------------------------------------

   if (newDistrb%numLocalBlocks > 0) then
      allocate (newDistrb%blockGlobalID(newDistrb%numLocalBlocks), &
                stat=istat)

      do j=1,nprocsY
      do i=1,nprocsX
         processor = (j-1)*nprocsX + i

         if (processor == my_task + 1) then
            is = (i-1)*numBlocksXPerProc + 1   ! starting block in i
            ie =  i   *numBlocksXPerProc       ! ending   block in i
            if (ie > nblocks_x) ie = nblocks_x
            js = (j-1)*numBlocksYPerProc + 1   ! starting block in j
            je =  j   *numBlocksYPerProc       ! ending   block in j
            if (je > nblocks_y) je = nblocks_y

            localID        = 0  ! initialize counter for local index
            do jblock = js,je
            do iblock = is,ie
               globalID = (jblock - 1)*nblocks_x + iblock
               if (workPerBlock(globalID) /= 0) then
                  localID = localID + 1
                  newDistrb%blockGlobalID (localID) = globalID
               endif
            end do
            end do

         endif

      end do
      end do

   endif

!----------------------------------------------------------------------
!EOC

 end function create_distrb_cart

!**********************************************************************
!BOP
! !IROUTINE: create_distrb_rake
! !INTERFACE:

 function create_distrb_rake(nprocs, workPerBlock) result(newDistrb)

! !DESCRIPTION:
!  This  function distributes blocks across processors in a
!  load-balanced manner based on the amount of work per block.
!  A rake algorithm is used in which the blocks are first distributed
!  in a Cartesian distribution and then a rake is applied in each
!  Cartesian direction.
!
! !REVISION HISTORY:
!  same as module

! !INPUT PARAMETERS:

   integer (int_kind), intent(in) :: &
      nprocs                ! number of processors in this distribution

   integer (int_kind), dimension(:), intent(in) :: &
      workPerBlock        ! amount of work per block

! !OUTPUT PARAMETERS:

   type (distrb) :: &
      newDistrb           ! resulting structure describing
                          ! load-balanced distribution of blocks

!EOP
!BOC
!----------------------------------------------------------------------
!
!  local variables
!
!----------------------------------------------------------------------

   integer (int_kind) ::    &
      i,j,n              ,&! dummy loop indices
      pid                ,&! dummy for processor id
      istat              ,&! status flag for allocates
      localBlock         ,&! local block position on processor
      numOcnBlocks       ,&! number of ocean blocks
      maxWork            ,&! max amount of work in any block
      nprocsX          ,&! num of procs in x for global domain
      nprocsY            ! num of procs in y for global domain

   integer (int_kind), dimension(:), allocatable :: &
      priority           ,&! priority for moving blocks
      workTmp            ,&! work per row or column for rake algrthm
      procTmp              ! temp processor id for rake algrthm

   type (distrb) :: dist  ! temp hold distribution

!----------------------------------------------------------------------
!
!  first set up as Cartesian distribution
!
!----------------------------------------------------------------------

   dist = create_distrb_cart(nprocs, workPerBlock)
                                    
!----------------------------------------------------------------------
!
!  if the number of blocks is close to the number of processors,
!  only do a 1-d rake on the entire distribution
!
!----------------------------------------------------------------------

   numOcnBlocks = count(workPerBlock /= 0)

   if (numOcnBlocks <= 2*nprocs) then

      allocate(priority(nblocks_tot), stat=istat)

      !*** initialize priority array

      do j=1,nblocks_y
      do i=1,nblocks_x
         n=(j-1)*nblocks_x + i
         if (workPerBlock(n) > 0) then
            priority(n) = maxWork + n - workPerBlock(n)
         else
            priority(n) = 0
         endif
      end do
      end do

      allocate(workTmp(nblocks_tot), procTmp(nblocks_tot), stat=istat)

      workTmp(:) = 0
      do i=1,nprocs
         procTmp(i) = i
         do n=1,nblocks_tot
            if (dist%blockLocation(n) == i) then
               workTmp(i) = workTmp(i) + workPerBlock(n)
            endif
         end do
      end do

      call ice_distributionRake (workTmp, procTmp, workPerBlock, &
                                 priority, dist)

      deallocate(workTmp, procTmp, stat=istat)

!----------------------------------------------------------------------
!
!  otherwise re-distribute blocks using a rake in each direction
!
!----------------------------------------------------------------------

   else

      maxWork = maxval(workPerBlock)

      call proc_decomposition(dist%nprocs, nprocsX, nprocsY)

!----------------------------------------------------------------------
!
!     load-balance using a rake algorithm in the x-direction first
!
!----------------------------------------------------------------------

      allocate(priority(nblocks_tot), stat=istat)

      !*** set highest priority such that eastern-most blocks
      !*** and blocks with the least amount of work are
      !*** moved first

      do j=1,nblocks_y
      do i=1,nblocks_x
         n=(j-1)*nblocks_x + i
         if (workPerBlock(n) > 0) then
            priority(n) = (maxWork + 1)*(nblocks_x + i) - &
                          workPerBlock(n)
         else
            priority(n) = 0
         endif
      end do
      end do

      allocate(workTmp(nprocsX), procTmp(nprocsX), stat=istat)

      do j=1,nprocsY

         workTmp(:) = 0
         do i=1,nprocsX
            pid = (j-1)*nprocsX + i
            procTmp(i) = pid
            do n=1,nblocks_tot
               if (dist%blockLocation(n) == pid) then
                  workTmp(i) = workTmp(i) + workPerBlock(n)
               endif
            end do
         end do

         call ice_distributionRake (workTmp, procTmp, workPerBlock, &
                                    priority, dist)
      end do
   
      deallocate(workTmp, procTmp, stat=istat)


!----------------------------------------------------------------------
!
!     use a rake algorithm in the y-direction now
!
!----------------------------------------------------------------------

      !*** set highest priority for northern-most blocks

      do j=1,nblocks_y
      do i=1,nblocks_x
         n=(j-1)*nblocks_x + i
         if (workPerBlock(n) > 0) then
            priority(n) = (maxWork + 1)*(nblocks_y + j) - &
                          workPerBlock(n)
         else
            priority(n) = 0
         endif
      end do
      end do

      allocate(workTmp(nprocsY), procTmp(nprocsY), stat=istat)

      do i=1,nprocsX

         workTmp(:) = 0
         do j=1,nprocsY
            pid = (j-1)*nprocsX + i
            procTmp(j) = pid
            do n=1,nblocks_tot
               if (dist%blockLocation(n) == pid) then
                  workTmp(j) = workTmp(j) + workPerBlock(n)
               endif
            end do
         end do

         call ice_distributionRake (workTmp, procTmp, workPerBlock, &
                                    priority, dist)

      end do

      deallocate(workTmp, procTmp, priority, stat=istat)

   endif  ! 1d or 2d rake

!----------------------------------------------------------------------
!
!  create new distribution with info extracted from the temporary
!  distribution
!
!----------------------------------------------------------------------

   newDistrb%nprocs     = nprocs
   newDistrb%communicator = dist%communicator

   allocate(newDistrb%blockLocation(nblocks_tot), &
            newDistrb%blockLocalID(nblocks_tot), stat=istat)

   allocate(procTmp(nprocs), stat=istat)

   procTmp = 0
   do n=1,nblocks_tot
      pid = dist%blockLocation(n)  ! processor id
      newDistrb%blockLocation(n) = pid

      if (pid > 0) then
         procTmp(pid) = procTmp(pid) + 1
         newDistrb%blockLocalID (n) = procTmp(pid)
      else
         newDistrb%blockLocalID (n) = 0
      endif
   end do

   newDistrb%numLocalBlocks = procTmp(my_task+1)

   if (minval(procTmp) < 1) then
      call abort_ice( &
         'create_distrb_rake: processors left with no blocks')
      return
   endif

   deallocate(procTmp, stat=istat)

   if (istat > 0) then
      call abort_ice( &
         'create_distrb_rake: error allocating last procTmp')
      return
   endif

   allocate(newDistrb%blockGlobalID(newDistrb%numLocalBlocks), &
            stat=istat)

   if (istat > 0) then
      call abort_ice( &
         'create_distrb_rake: error allocating blockGlobalID')
      return
   endif

   localBlock = 0
   do n=1,nblocks_tot
      if (newDistrb%blockLocation(n) == my_task+1) then
         localBlock = localBlock + 1
         newDistrb%blockGlobalID(localBlock) = n
      endif
   end do

!----------------------------------------------------------------------

   call ice_distributionDestroy(dist)

!----------------------------------------------------------------------
!EOC

 end function create_distrb_rake

!**********************************************************************
!BOP
! !IROUTINE: create_distrb_spacecurve
! !INTERFACE:

 function create_distrb_spacecurve(nprocs,work_per_block)

! !Description:
!  This function distributes blocks across processors in a
!  load-balanced manner using space-filling curves
!
! !REVISION HISTORY:
!  added by J. Dennis 3/10/06

! !INPUT PARAMETERS:

   integer (int_kind), intent(in) :: &
      nprocs                ! number of processors in this distribution

   integer (int_kind), dimension(:), intent(in) :: &
      work_per_block        ! amount of work per block

! !OUTPUT PARAMETERS:

   type (distrb) :: &
      create_distrb_spacecurve  ! resulting structure describing
                                ! load-balanced distribution of blocks
!EOP
!BOC
!----------------------------------------------------------------------

!
!  local variables
!
!----------------------------------------------------------------------

   integer (int_kind) :: &
      i,j,k,n              ,&! dummy loop indices
      pid                  ,&! dummy for processor id
      localID              ,&! local block position on processor
      max_work             ,&! max amount of work in any block
      nprocs_x             ,&! num of procs in x for global domain
      nprocs_y               ! num of procs in y for global domain

   integer (int_kind), dimension(:),allocatable :: &
        idxT_i,idxT_j       ! Temporary indices for SFC

   integer (int_kind), dimension(:,:),allocatable :: &
        Mesh            ,&!   !arrays to hold Space-filling curve
        Mesh2             !

   integer (int_kind) :: &
        nblocksL,nblocks, &! Number of blocks local and total
        ii,extra,tmp1,    &! loop tempories used for
        s1,ig              ! partitioning curve

   logical, parameter :: Debug = .FALSE.

   integer (int_kind), dimension(:), allocatable :: &
      priority           ,&! priority for moving blocks
      work_tmp           ,&! work per row or column for rake algrthm
      proc_tmp           ,&! temp processor id for rake algrthm
      block_count          ! counter to determine local block indx

   type (distrb) :: dist  ! temp hold distribution

!------------------------------------------------------
! Space filling curves only work if:
!
!    nblocks_x = nblocks_y
!       nblocks_x = 2^m 3^n 5^p where m,n,p are integers
!------------------------------------------------------
   if((nblocks_x /= nblocks_y) .or. (.not. IsFactorable(nblocks_x))) then
     create_distrb_spacecurve = create_distrb_cart(nprocs, work_per_block)
     return
   endif

   call create_communicator(dist%communicator, nprocs)

   dist%nprocs = nprocs

!----------------------------------------------------------------------
!
!  allocate space for decomposition
!
!----------------------------------------------------------------------

   allocate (dist%blockLocation(nblocks_tot), &
             dist%blockLocalID (nblocks_tot))

   dist%blockLocation=0
   dist%blockLocalID =0

!----------------------------------------------------------------------
!  Create the array to hold the SFC and indices into it
!----------------------------------------------------------------------
   allocate(Mesh(nblocks_x,nblocks_y))
   allocate(Mesh2(nblocks_x,nblocks_y))
   allocate(idxT_i(nblocks_tot),idxT_j(nblocks_tot))

   Mesh  = 0
   Mesh2 = 0

!----------------------------------------------------------------------
!  Generate the space-filling curve
!----------------------------------------------------------------------
   call GenSpaceCurve(Mesh)
   if(Debug) then
     if(my_task ==0) call PrintCurve(Mesh)
   endif
   !------------------------------------------------
   ! create a linear array of i,j coordinates of SFC
   !------------------------------------------------
   idxT_i=0;idxT_j=0
   do j=1,nblocks_y
     do i=1,nblocks_x
        n = (j-1)*nblocks_x + i
        ig = Mesh(i,j)
        if(work_per_block(n) /= 0) then
            idxT_i(ig+1)=i;idxT_j(ig+1)=j
        endif
     enddo
   enddo
   !-----------------------------
   ! Compress out the land blocks
   !-----------------------------
   ii=0
   do i=1,nblocks_tot
      if(IdxT_i(i) .gt. 0) then
         ii=ii+1
         Mesh2(idxT_i(i),idxT_j(i)) = ii
      endif
   enddo
   nblocks=ii
   if(Debug) then
     if(my_task==0) call PrintCurve(Mesh2)
   endif

   !----------------------------------------------------
   ! Compute the partitioning of the space-filling curve
   !----------------------------------------------------
   nblocksL = nblocks/nprocs
   ! every cpu gets nblocksL blocks, but the first 'extra' get nblocksL+1
   extra = mod(nblocks,nprocs)
   s1 = extra*(nblocksL+1)
   ! split curve into two curves:
   ! 1 ... s1  s2 ... nblocks
   !
   !  s1 = extra*(nblocksL+1)         (count be 0)
   !  s2 = s1+1
   !
   ! First region gets nblocksL+1 blocks per partition
   ! Second region gets nblocksL blocks per partition
   if(Debug) print *,'nprocs,extra,nblocks,nblocksL,s1: ', &
                nprocs,extra,nblocks,nblocksL,s1

   !-----------------------------------------------------------
   ! Use the SFC to partition the blocks across processors
   !-----------------------------------------------------------
   do j=1,nblocks_y
   do i=1,nblocks_x
      n = (j-1)*nblocks_x + i
      ii = Mesh2(i,j)
      if(ii>0) then
        if(ii<=s1) then
           ! ------------------------------------
           ! If on the first region of curve
           ! all processes get nblocksL+1 blocks
           ! ------------------------------------
           ii=ii-1
           tmp1 = ii/(nblocksL+1)
           dist%blockLocation(n) = tmp1+1
        else
           ! ------------------------------------
           ! If on the second region of curve
           ! all processes get nblocksL blocks
           ! ------------------------------------
           ii=ii-s1-1
           tmp1 = ii/nblocksL
           dist%blockLocation(n) = extra + tmp1 + 1
        endif
      endif
   enddo
   enddo

!----------------------------------------------------------------------
!  Reset the dist data structure
!----------------------------------------------------------------------

   allocate(proc_tmp(nprocs))
   proc_tmp = 0

   do n=1,nblocks_tot
      pid = dist%blockLocation(n)
      dist%blockLocation(n) = pid

      if(pid>0) then
        proc_tmp(pid) = proc_tmp(pid) + 1
        dist%blockLocalID(n) = proc_tmp(pid)
      else
        dist%blockLocalID(n) = 0
      endif
   enddo

   dist%numLocalBlocks = proc_tmp(my_task+1)

   if (dist%numLocalBlocks > 0) then
      allocate (dist%blockGlobalID(dist%numLocalBlocks))
      dist%blockGlobalID = 0
   endif
   localID = 0
   do n=1,nblocks_tot
      if (dist%blockLocation(n) == my_task+1) then
         localID = localID + 1
         dist%blockGlobalID(localID) = n
      endif
   enddo

   if(Debug) then
      if(my_task==0) print *,'dist%blockLocation:= ',dist%blockLocation
      print *,'IAM: ',my_task,' SpaceCurve: Number of blocks {total,local} :=', &
                nblocks_tot,nblocks,proc_tmp(my_task+1)
   endif
   !---------------------------------
   ! Deallocate temporary arrays
   !---------------------------------
   deallocate(proc_tmp)
   deallocate(Mesh,Mesh2)
   deallocate(idxT_i,idxT_j)
!----------------------------------------------------------------------
   create_distrb_spacecurve = dist  ! return the result

!----------------------------------------------------------------------
!EOC

 end function create_distrb_spacecurve

!**********************************************************************
!BOP
! !IROUTINE: ice_distributionRake
! !INTERFACE:

 subroutine ice_distributionRake (procWork, procID, blockWork, &
                                  priority, distribution)

! !DESCRIPTION:
!  This subroutine performs a rake algorithm to distribute the work
!  along a vector of processors.  In the rake algorithm, a work
!  threshold is first set.  Then, moving from left to right, work
!  above that threshold is raked to the next processor in line.
!  The process continues until the end of the vector is reached
!  and then the threshold is reduced by one for a second rake pass.
!  In this implementation, a priority for moving blocks is defined
!  such that the rake algorithm chooses the highest priority
!  block to be moved to the next processor.  This can be used
!  for example to always choose the eastern-most block or to
!  ensure a block does not stray too far from its neighbors.
!
! !REVISION HISTORY:
!  same as module

! !INPUT PARAMETERS:

   integer (int_kind), intent(in), dimension(:) :: &
      blockWork          ,&! amount of work per block
      procID               ! global processor number

! !INPUT/OUTPUT PARAMETERS:

   integer (int_kind), intent(inout), dimension(:) :: &
      procWork           ,&! amount of work per processor
      priority             ! priority for moving a given block

   type (distrb), intent(inout) :: &
      distribution         ! distribution to change

! !OUTPUT PARAMETERS:

!EOP
!BOC
!----------------------------------------------------------------------
!
!  local variables
!
!----------------------------------------------------------------------

   integer (int_kind) :: &
      i, n,                  &! dummy loop indices
      np1,                   &! n+1 corrected for cyclical wrap
      iproc, inext,          &! processor ids for current and next 
      nprocs, numBlocks,   &! number of blocks, processors
      lastPriority,          &! priority for most recent block
      minPriority,           &! minimum priority
      lastLoc,               &! location for most recent block
      meanWork, maxWork,     &! mean,max work per processor
      diffWork, residual,    &! work differences and residual work
      numTransfers            ! counter for number of block transfers

!----------------------------------------------------------------------
!
!  initialization
!
!----------------------------------------------------------------------

   nprocs  = size(procWork)
   numBlocks = size(blockWork)

   !*** compute mean,max work per processor

   meanWork = sum(procWork)/nprocs + 1
   maxWork  = maxval(procWork)
   residual = mod(meanWork,nprocs)

   minPriority = 1000000
   do n=1,nprocs
      iproc = procID(n)
      do i=1,numBlocks
         if (distribution%blockLocation(i) == iproc) then
            minPriority = min(minPriority,priority(i))
         endif
      end do
   end do

!----------------------------------------------------------------------
!
!  do two sets of transfers
!
!----------------------------------------------------------------------

   transferLoop: do

!----------------------------------------------------------------------
!
!     do rake across the processors
!
!----------------------------------------------------------------------

      numTransfers = 0
      do n=1,nprocs
         if (n < nprocs) then
            np1   = n+1
         else
            np1   = 1
         endif
         iproc = procID(n)
         inext = procID(np1)

         if (procWork(n) > meanWork) then !*** pass work to next

            diffWork = procWork(n) - meanWork

            rake1: do while (diffWork > 1)

               !*** attempt to find a block with the required
               !*** amount of work and with the highest priority
               !*** for moving (eg boundary blocks first)

               lastPriority = 0
               lastLoc = 0

               do i=1,numBlocks
                  if (distribution%blockLocation(i) == iproc) then
                     if (priority(i) > lastPriority ) then
                        lastPriority = priority(i)
                        lastLoc = i
                     endif
                  endif
               end do
               if (lastLoc == 0) exit rake1 ! could not shift work

               numTransfers = numTransfers + 1
               distribution%blockLocation(lastLoc) = inext
               if (np1 == 1) priority(lastLoc) = minPriority
               diffWork = diffWork - blockWork(lastLoc)

               procWork(n  ) = procWork(n  )-blockWork(lastLoc)
               procWork(np1) = procWork(np1)+blockWork(lastLoc)
            end do rake1
         endif

      end do

!----------------------------------------------------------------------
!
!     increment meanWork by one and repeat
!
!----------------------------------------------------------------------

      meanWork = meanWork + 1
      if (numTransfers == 0 .or. meanWork > maxWork) exit transferLoop

   end do transferLoop

!----------------------------------------------------------------------
!EOC

end subroutine ice_distributionRake

!***********************************************************************

end module ice_distribution

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
