program iso_interp_met

  !MESA modules
  use const_def, only: dp
  use utils_lib
  use interp_1d_def
  use interp_1d_lib

  !local modules
  use iso_eep_support
  use iso_color

  implicit none

  type(isochrone_set), allocatable :: s(:)
  type(isochrone_set) :: t
  real(dp), allocatable :: Z_div_H(:)
  real(dp) :: new_Z_div_H
  integer :: ierr, n, i, i_Minit
  logical :: do_colors
  logical, parameter :: force_linear = .false.
  logical, parameter :: debug = .false.
  
  call read_interp_input(ierr)
  if(ierr/=0) stop ' iso_interp_met: failed reading input list'

  do i=1,n
     call read_isochrone_file(s(i),ierr)
     if(ierr/=0)  stop ' iso_interp_met: failed in read_isochrone_file'
  enddo

  !need this for PAV
  i_Minit=locate_Minit(s(1)% iso(1))

  call consistency_check(s,ierr)
  if(ierr/=0) stop ' iso_interp_met: failed consistency check(s)'

  !if all checks pass, then proceed with interpolation
  call interpolate_Z(n,Z_div_H,new_Z_div_H,s,t,ierr)

  !write the new isochrone to file
  if(ierr==0) then
     call write_isochrones_to_file(t)
     if(do_colors) call write_cmds_to_file(t)
  endif

contains

  function locate_Minit(iso) result(i)
    type(isochrone), intent(in) :: iso
    integer :: i, j
    do j=1,iso% ncol
       if(trim(adjustl(iso% cols(j)% name))=='initial_mass')then
          i=j
          return
       endif
    enddo
    i=0
  end function locate_Minit

  subroutine read_interp_input(ierr)
    integer, intent(out) :: ierr
    integer :: io, i
    character(len=file_path) :: iso_list, arg
    character(len=file_path) :: bc_list, cstar_list
    ierr = 0
    do_colors = .false.

    if(command_argument_count() < 3) then
       ierr=-1
       write(0,*) 'iso_interp_met        '
       write(0,*) '   usage:             '
       write(0,*) ' ./iso_interp_met [list] [Z/H] [output] [Av]'
       write(0,*) '  Av is optional;                       '
       write(0,*) '   will generate a .cmd file if included'
       return
    else if(command_argument_count() > 3) then
       do_colors=.true.
       t% cmd_suffix = 'cmd'
       bc_list = 'bc_table.list'
       cstar_list = 'cstar_table.list'
       call iso_color_init(bc_list,.false.,cstar_list,ierr)
       if(ierr/=0) then 
          write(0,'(a)') ' problem reading BC_table_list = ', trim(bc_list)
          do_colors=.false.
       endif
    endif

    call get_command_argument(1,iso_list)
    call get_command_argument(2,arg)
    read(arg,*) new_Z_div_H
    call get_command_argument(3,t% filename)
    if(do_colors)then
       call get_command_argument(4, arg)
       read(arg,*) t% Av
       t% Rv = 3.1
    endif

    io=alloc_iounit(ierr)
    open(io,file=trim(iso_list),action='read',status='old')
    read(io,*) n
    allocate(s(n),Z_div_H(n))
    do i=1,n
       read(io,'(f5.2,1x,a)') Z_div_H(i), s(i)% filename
    enddo
    close(io)
    call free_iounit(io)
  end subroutine read_interp_input


  subroutine consistency_check(s,ierr)
    type(isochrone_set), intent(in) :: s(:)
    integer, intent(out) :: ierr
    integer :: n, i

    ierr = 0

    n=size(s)

    if(any(s(:)% number_of_isochrones /= s(1)% number_of_isochrones))then
       write(0,*) ' iso_interp_met : failed consistency check - inconsistent number of isochrones '
       ierr=-1
       do i=1,n
          write(0,*) trim(s(i)% filename), s(i)% version_number
       enddo
    endif

    if(any(s(:)% version_number /= s(1)% version_number))then
       write(0,*) ' iso_interp_met : failed consistency check - inconsistent version number '
       ierr=-1
       do i=1,n
          write(0,*) trim(s(i)% filename), s(i)% number_of_isochrones
       enddo
    endif

    !more checks here as needed

  end subroutine consistency_check


  subroutine interpolate_Z(n,Z,newZ,s,t,ierr)
    integer, intent(in) :: n
    real(dp), intent(in) :: Z(n), newZ
    type(isochrone_set), intent(in) :: s(n)
    type(isochrone_set), intent(inout) :: t
    integer, intent(out) :: ierr
    integer :: i, loc, lo, hi, order
    loc=0; order=0; lo=0; hi=0

    ierr = 0

    do i=1,n-1
       if(newZ >= Z(i) .and. newZ < Z(i+1)) then
          loc=i
          exit
       endif
    enddo

    if(loc==0)then
       ierr=-1
       write(0,*) ' iso_interp_met: no extrapolation! '
       return
    endif

    !this results in either cubic (order=4) or linear (order=2)
    if(force_linear)then
       lo=loc
       hi=loc+1
    elseif(loc==n-1 .or. loc==1)then
       lo=loc
       hi=loc+1
    else
       lo=loc-1
       hi=loc+2
    endif

    order = hi - lo + 1  ! either 4, 3, or 2

    t% number_of_isochrones =s(lo)% number_of_isochrones
    t% version_number = s(lo)% version_number
    allocate(t% iso(t% number_of_isochrones))
    t% iso(:)% age_scale = s(lo)% iso(:)% age_scale
    t% iso(:)% has_phase = s(lo)% iso(:)% has_phase
    t% iso(:)% age       = s(lo)% iso(:)% age
    t% iso(:)% ncol      = s(lo)% iso(:)% ncol
    do i = 1, t% number_of_isochrones
       allocate(t% iso(i)% cols(t% iso(i)% ncol))
       t% iso(i)% cols(:)% name = s(lo)% iso(i)% cols(:)% name
       t% iso(i)% cols(:)% type = s(lo)% iso(i)% cols(:)% type
       t% iso(i)% cols(:)% loc = s(lo)% iso(i)% cols(:)% loc
    enddo

    call do_interp(order,Z(lo:hi),newZ,s(lo:hi),t)

    !PAV?
    do i=1,t% number_of_isochrones
       call PAV(t% iso(i)% data(i_Minit,:))
    enddo

  end subroutine interpolate_Z


  subroutine do_interp(n,Z,newZ,s,t)
    integer, intent(in) :: n
    real(dp), intent(in) :: Z(n), newZ
    type(isochrone_set), intent(in) :: s(n)
    type(isochrone_set), intent(inout) :: t
    integer :: i, j, k, neep, eeps_lo(n), eeps_hi(n)
    integer :: eep, eep_lo, eep_hi, ioff(n), ncol
    logical :: eep_good(n)
    logical, pointer :: good(:)=>NULL()
    integer, pointer :: new_eep(:)=>NULL()

    do i=1,n
       write(*,*) trim(s(i)% filename), Z(i)
    enddo

    do i=1,t% number_of_isochrones
       do j=1,n
          eeps_lo(j) = s(j)% iso(i)% eep(1)
          neep=s(j)% iso(i)% neep
          eeps_hi(j) = s(j)% iso(i)% eep(neep)
       enddo
       eep_lo = maxval(eeps_lo)
       eep_hi = minval(eeps_hi)

       allocate(good(eep_hi),new_eep(eep_hi))
       good=.false.
       new_eep=0
       neep=0
       eep_loop: do eep=eep_lo, eep_hi
          eep_good=.false.
          j_loop: do j=1,n
             k_loop: do k=1,s(j)% iso(i)% neep
                if(s(j)% iso(i)% eep(k)==eep)then
                   eep_good(j)=.true.
                   exit k_loop
                endif
             enddo k_loop
          enddo j_loop
          if(all(eep_good,1)) then
             neep = neep + 1
             good(eep) = .true.
             new_eep(eep) = neep
          elseif(debug)then
             write(*,*) ' bad EEP = ', eep
          endif
       enddo eep_loop

       t% iso(i)% neep = neep
       ncol = t% iso(i)% ncol
       allocate(t% iso(i)% eep(neep), t% iso(i)% data(ncol,neep))
       t% iso(i)% eep  = 0
       t% iso(i)% data = 0d0

       if(t% iso(i)% has_phase) then
          allocate(t% iso(i)% phase(neep))      
          t% iso(i)% phase = 0d0
       endif

       !loop over the EEPs
!$omp parallel do private(eep,ioff)
       do eep=eep_lo, eep_hi
          if(good(eep)) then
             t% iso(i)% eep(new_eep(eep)) = eep
             ioff=0
             do j=1,n
                do k=1,s(j)% iso(i)% neep
                   if(s(j)% iso(i)% eep(k) == eep)then
                      ioff(j)=k
                      exit
                   endif
                enddo
             enddo
             if(t%iso(i)% has_phase) t% iso(i)% phase(new_eep(eep)) = s(1)% iso(i)% phase(ioff(1))
             if(n==2)then 
                t% iso(i)% data(:,new_eep(eep)) = linear( ncol, Z, newZ, &
                     s(1)% iso(i)% data(:,ioff(1)), &
                     s(2)% iso(i)% data(:,ioff(2)) )
             else if(n==4) then
                t% iso(i)% data(:,new_eep(eep)) = cubic_pm( ncol, Z, newZ, &
                     s(1)% iso(i)% data(:,ioff(1)), &
                     s(2)% iso(i)% data(:,ioff(2)), &
                     s(3)% iso(i)% data(:,ioff(3)), &
                     s(4)% iso(i)% data(:,ioff(4)) )
             endif
          endif
       enddo
!$omp end parallel do
       deallocate(good)
       nullify(good)
    enddo
  end subroutine do_interp

  function linear(ncol,Z,newZ,x,y) result(res)
    integer, intent(in) :: ncol
    real(dp), intent(in) :: Z(2), newZ, x(ncol), y(ncol)
    real(dp) :: res(ncol), alfa, beta
    alfa = (Z(2)-newZ)/(Z(2)-Z(1))
    beta = 1d0 - alfa
    res = alfa*x + beta*y
  end function linear

  function cubic_pm(ncol,Z,newZ,v,w,x,y) result(res)
    integer, intent(in) :: ncol
    real(dp), intent(in) :: Z(4), newZ, v(ncol), w(ncol), x(ncol), y(ncol)
    real(dp) :: res(ncol), Q(4), a(3), dZ
    integer :: i, ierr
    ierr= 0
    dZ = newZ - Z(2)
    do i=1,ncol
       Q=[v(i),w(i),x(i),y(i)]
       call interp_4pt_pm(Z, Q, a)
       res(i) = Q(2) + dZ*(a(1) + dZ*(a(2) + dZ*a(3)))
    enddo
  end function cubic_pm

!!$  function quadratic(ncol,Z,newZ,w,x,y) result(res)
!!$    integer, intent(in) :: ncol
!!$    real(dp), intent(in) :: Z(3), newZ, w(ncol), x(ncol), y(ncol)
!!$    real(dp) :: res(ncol), x12, x23, x00
!!$    integer :: i, ierr
!!$    character(len=file_path) :: str
!!$    ierr= 0
!!$    x00 = newZ - Z(1) 
!!$    x12 = Z(2) - Z(1)
!!$    x23 = Z(3) - Z(2)
!!$    do i=1,ncol
!!$       call interp_3_to_1(x12, x23, x00, w(i), x(i), y(i), res(i), str, ierr)
!!$    enddo
!!$  end function quadratic

!!$
!!$  function cubic(ncol,Z,newZ,v,w,x,y) result(res)
!!$    integer, intent(in) :: ncol
!!$    real(dp), intent(in) :: Z(4), newZ, v(ncol), w(ncol), x(ncol), y(ncol)
!!$    real(dp) :: res(ncol), x12, x23, x34, x00
!!$    integer :: i, ierr
!!$    character(len=file_path) :: str
!!$    ierr= 0
!!$    x00 = newZ - Z(1)
!!$    x12 = Z(2) - Z(1)
!!$    x23 = Z(3) - Z(2)
!!$    x34 = Z(4) - Z(3)
!!$    do i=1,ncol
!!$       call interp_4_to_1(x12, x23, x34, x00, v(i), w(i), x(i), y(i), res(i), str, ierr)
!!$    enddo
!!$  end function cubic
!!$
!!$
!!$  function cubic_generic(ncol,Z,newZ,v,w,x,y) result(res)
!!$    integer, intent(in) :: ncol
!!$    real(dp), intent(in) :: Z(4), newZ, v(ncol), w(ncol), x(ncol), y(ncol)
!!$    real(dp) :: res(ncol), Q(4), x_new(1), y_new(1)
!!$    integer, parameter :: nwork = max(pm_work_size, mp_work_size)        
!!$    real(dp), target :: work_ary(4*nwork)
!!$    real(dp), pointer :: work(:)
!!$    integer :: i, ierr
!!$    character(len=file_path) :: str
!!$
!!$    work => work_ary
!!$    x_new(1) = newZ
!!$    ierr= 0
!!$    do i=1,ncol
!!$       Q=[v(i),w(i),x(i),y(i)]
!!$       call interpolate_vector(4, Z, 1, x_new, Q, y_new, interp_m3q, nwork, work, str, ierr)
!!$       res(i) = y_new(1)
!!$    enddo
!!$  end function cubic_generic


end program iso_interp_met