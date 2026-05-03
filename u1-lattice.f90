program u1_lattice_gauge
  use mpi
  implicit none

  ! U(1) pure gauge lattice simulation (Wilson action) with MPI.
  !
  ! Links: U_mu(x) = exp(i * theta_mu(x)), theta in (-pi, pi].
  ! Action: S = -beta * sum_{plaquettes} cos(theta_p).
  ! Update: Metropolis per-link using local staple.
  ! Parallelism: 1D slab decomposition in t dimension with 1-slice halos.

  integer :: ierr, rank, nprocs
  integer :: L, sweeps, therm, measureEvery
  real    :: beta, delta

  integer :: Nt, t0, t1, Ntloc

  real, parameter :: pi = 3.14159265358979323846

  ! theta(mu, x, y, z, tlocal) ; tlocal includes halos 0..Ntloc+1
  real, allocatable :: theta(:,:,:,:,:)

  call MPI_Init(ierr)
  call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
  call MPI_Comm_size(MPI_COMM_WORLD, nprocs, ierr)

  ! Defaults
  L = 8
  beta = 1.0
  sweeps = 200
  therm = 50
  delta = 0.4
  measureEvery = 10

  call parse_args(L, beta, sweeps, therm, delta, measureEvery)

  Nt = L
  call decompose_1d(Nt, nprocs, rank, t0, t1)
  Ntloc = t1 - t0 + 1

  allocate(theta(0:3, 1:L, 1:L, 1:L, 0:Ntloc+1))

  call init_links(theta, L, Ntloc, rank)

  if (rank == 0) then
    write(*,'(a)') 'U(1) lattice gauge (Wilson) with MPI'
    write(*,'(a,i0,a,f6.3,a,i0,a,i0,a,f6.3)') 'L=',L,' beta=',beta,' sweeps=',sweeps,' therm=',therm,' delta=',delta
    write(*,'(a,i0)') 'MPI ranks=', nprocs
  end if

  call halo_exchange(theta, L, Ntloc, rank, nprocs)
  call run_mc(theta, L, Ntloc, beta, delta, sweeps, therm, measureEvery, rank, nprocs)

  call MPI_Finalize(ierr)

contains

  subroutine parse_args(L, beta, sweeps, therm, delta, measureEvery)
    implicit none
    integer, intent(inout) :: L, sweeps, therm, measureEvery
    real,    intent(inout) :: beta, delta
    integer :: nargs
    character(len=256) :: arg

    nargs = command_argument_count()
    if (nargs >= 1) then
      call get_command_argument(1,arg); read(arg,*) L
    end if
    if (nargs >= 2) then
      call get_command_argument(2,arg); read(arg,*) beta
    end if
    if (nargs >= 3) then
      call get_command_argument(3,arg); read(arg,*) sweeps
    end if
    if (nargs >= 4) then
      call get_command_argument(4,arg); read(arg,*) therm
    end if
    if (nargs >= 5) then
      call get_command_argument(5,arg); read(arg,*) delta
    end if
    if (nargs >= 6) then
      call get_command_argument(6,arg); read(arg,*) measureEvery
    end if
  end subroutine parse_args

  subroutine decompose_1d(N, P, r, a0, a1)
    implicit none
    integer, intent(in)  :: N, P, r
    integer, intent(out) :: a0, a1
    integer :: base, rem

    base = N / P
    rem  = mod(N, P)

    if (r < rem) then
      a0 = r*(base+1) + 1
      a1 = a0 + (base+1) - 1
    else
      a0 = rem*(base+1) + (r-rem)*base + 1
      a1 = a0 + base - 1
    end if
  end subroutine decompose_1d

  subroutine init_links(theta, L, Ntloc, rank)
    implicit none
    integer, intent(in) :: L, Ntloc, rank
    real, intent(inout) :: theta(0:3, 1:L,1:L,1:L, 0:Ntloc+1)
    integer :: mu, x,y,z,t
    integer(kind=8) :: rng

    rng = 88172645463325252_8 + 1337_8*rank

    do t = 1, Ntloc
      do z = 1, L
        do y = 1, L
          do x = 1, L
            do mu = 0, 3
              theta(mu,x,y,z,t) = (2.0*pi)*(randu(rng) - 0.5)
            end do
          end do
        end do
      end do
    end do

    theta(:,:,:,:,0) = 0.0
    theta(:,:,:,:,Ntloc+1) = 0.0
  end subroutine init_links

  real function randu(state)
    implicit none
    integer(kind=8), intent(inout) :: state
    ! xorshift64*
    state = ieor(state, ishft(state, 12))
    state = ieor(state, ishft(state, -25))
    state = ieor(state, ishft(state, 27))
    state = state * 2685821657736338717_8
    randu = real(iand(state, int(z'7fffffffffffffff',8))) / real(huge(1_8))
  end function randu

  subroutine halo_exchange(theta, L, Ntloc, rank, nprocs)
    use mpi
    implicit none
    integer, intent(in) :: L, Ntloc, rank, nprocs
    real, intent(inout) :: theta(0:3,1:L,1:L,1:L,0:Ntloc+1)

    integer :: up, down, ierr
    integer :: count
    real, allocatable :: sendUp(:), sendDown(:), recvUp(:), recvDown(:)

    up   = mod(rank-1+nprocs, nprocs)
    down = mod(rank+1, nprocs)

    count = 4*L*L*L
    allocate(sendUp(count), sendDown(count), recvUp(count), recvDown(count))

    call pack_slice(theta, L, Ntloc, 1, sendUp)
    call pack_slice(theta, L, Ntloc, Ntloc, sendDown)

    ! recvDown gets neighbour's first slice (their t=1) -> our halo Ntloc+1
    call MPI_Sendrecv(sendUp,   count, MPI_REAL, up,   101, recvDown, count, MPI_REAL, down, 101, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)
    ! recvUp gets neighbour's last slice (their t=Ntloc) -> our halo 0
    call MPI_Sendrecv(sendDown, count, MPI_REAL, down, 102, recvUp,   count, MPI_REAL, up,   102, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)

    call unpack_slice(theta, L, Ntloc, 0,       recvUp)
    call unpack_slice(theta, L, Ntloc, Ntloc+1, recvDown)

    deallocate(sendUp, sendDown, recvUp, recvDown)
  end subroutine halo_exchange

  subroutine pack_slice(theta, L, Ntloc, tIndex, buf)
    implicit none
    integer, intent(in) :: L, Ntloc, tIndex
    real, intent(in) :: theta(0:3,1:L,1:L,1:L,0:Ntloc+1)
    real, intent(out) :: buf(:)
    integer :: mu,x,y,z,k

    k = 1
    do mu=0,3
      do z=1,L
        do y=1,L
          do x=1,L
            buf(k) = theta(mu,x,y,z,tIndex)
            k = k + 1
          end do
        end do
      end do
    end do
  end subroutine pack_slice

  subroutine unpack_slice(theta, L, Ntloc, tIndex, buf)
    implicit none
    integer, intent(in) :: L, Ntloc, tIndex
    real, intent(inout) :: theta(0:3,1:L,1:L,1:L,0:Ntloc+1)
    real, intent(in) :: buf(:)
    integer :: mu,x,y,z,k

    k = 1
    do mu=0,3
      do z=1,L
        do y=1,L
          do x=1,L
            theta(mu,x,y,z,tIndex) = buf(k)
            k = k + 1
          end do
        end do
      end do
    end do
  end subroutine unpack_slice

  subroutine run_mc(theta, L, Ntloc, beta, delta, sweeps, therm, measureEvery, rank, nprocs)
    use mpi
    implicit none
    integer, intent(in) :: L, Ntloc, sweeps, therm, measureEvery, rank, nprocs
    real, intent(in) :: beta, delta
    real, intent(inout) :: theta(0:3,1:L,1:L,1:L,0:Ntloc+1)

    integer :: s
    real :: plaq_local, plaq_global
    integer(kind=8) :: rng

    rng = 1469598103934665603_8 + 99991_8*rank

    do s = 1, sweeps
      call sweep_metropolis(theta, L, Ntloc, beta, delta, rng, rank, nprocs)

      if (s >= therm .and. (mod(s-therm, measureEvery) == 0)) then
        plaq_local = plaquette_avg_local(theta, L, Ntloc)
        call MPI_Allreduce(plaq_local, plaq_global, 1, MPI_REAL, MPI_SUM, MPI_COMM_WORLD, ierr)
        plaq_global = plaq_global / real(nprocs)
        if (rank == 0) then
          write(*,'(a,i6,a,f10.6)') 'sweep=', s, ' <plaq>=', plaq_global
        end if
      end if
    end do
  end subroutine run_mc

  subroutine sweep_metropolis(theta, L, Ntloc, beta, delta, rng, rank, nprocs)
    implicit none
    integer, intent(in) :: L, Ntloc, rank, nprocs
    real, intent(in) :: beta, delta
    integer(kind=8), intent(inout) :: rng
    real, intent(inout) :: theta(0:3,1:L,1:L,1:L,0:Ntloc+1)

    integer :: x,y,z,t, mu
    real :: oldth, newth
    complex :: staple
    real :: rold, rnew, dS, acc

    call halo_exchange(theta, L, Ntloc, rank, nprocs)

    do t = 1, Ntloc
      do z = 1, L
        do y = 1, L
          do x = 1, L
            do mu = 0, 3
              oldth = theta(mu,x,y,z,t)
              staple = compute_staple(theta, L, Ntloc, x,y,z,t, mu)

              rold = real( cmplx(cos(oldth), sin(oldth)) * conjg(staple) )

              newth = wrap_angle(oldth + (2.0*randu(rng)-1.0)*delta)
              rnew = real( cmplx(cos(newth), sin(newth)) * conjg(staple) )

              dS = -beta * (rnew - rold)

              if (dS <= 0.0) then
                theta(mu,x,y,z,t) = newth
              else
                acc = exp(-dS)
                if (randu(rng) < acc) theta(mu,x,y,z,t) = newth
              end if
            end do
          end do
        end do
      end do
    end do
  end subroutine sweep_metropolis

  complex function compute_staple(theta, L, Ntloc, x,y,z,t, mu) result(st)
    implicit none
    integer, intent(in) :: L, Ntloc, x,y,z,t, mu
    real, intent(in) :: theta(0:3,1:L,1:L,1:L,0:Ntloc+1)
    integer :: nu
    integer :: xp,yp,zp,tp
    integer :: xm,ym,zm,tm
    real :: a1,a2,a3

    st = (0.0, 0.0)

    do nu = 0, 3
      if (nu == mu) cycle

      ! Forward staple: U_nu(x) U_mu(x+nu) U_nu^*(x+mu)
      call shift_site(L, Ntloc, x,y,z,t, nu, +1, xp,yp,zp,tp)
      a1 = theta(nu, x,y,z,t)
      a2 = theta(mu, xp,yp,zp,tp)
      call shift_site(L, Ntloc, x,y,z,t, mu, +1, xp,yp,zp,tp)
      a3 = theta(nu, xp,yp,zp,tp)
      st = st + cmplx(cos(a1 + a2 - a3), sin(a1 + a2 - a3))

      ! Backward staple: U_nu^*(x-nu) U_mu(x-nu) U_nu(x-nu+mu)
      call shift_site(L, Ntloc, x,y,z,t, nu, -1, xm,ym,zm,tm)
      a1 = theta(nu, xm,ym,zm,tm)          ! conjugated
      a2 = theta(mu, xm,ym,zm,tm)
      call shift_site(L, Ntloc, xm,ym,zm,tm, mu, +1, xp,yp,zp,tp)
      a3 = theta(nu, xp,yp,zp,tp)
      st = st + cmplx(cos(-a1 + a2 + a3), sin(-a1 + a2 + a3))
    end do
  end function compute_staple

  subroutine shift_site(L, Ntloc, x,y,z,t, dir, step, xo,yo,zo,to)
    implicit none
    integer, intent(in) :: L, Ntloc, x,y,z,t, dir, step
    integer, intent(out) :: xo,yo,zo,to

    xo = x; yo = y; zo = z; to = t

    select case (dir)
    case (0)
      xo = x + step
      if (xo < 1) xo = L
      if (xo > L) xo = 1
    case (1)
      yo = y + step
      if (yo < 1) yo = L
      if (yo > L) yo = 1
    case (2)
      zo = z + step
      if (zo < 1) zo = L
      if (zo > L) zo = 1
    case (3)
      to = t + step
      ! t is local with halos; halo_exchange provides periodic neighbours.
      if (to < 0) to = 0
      if (to > Ntloc+1) to = Ntloc+1
    end select
  end subroutine shift_site

  real function wrap_angle(a)
    implicit none
    real, intent(in) :: a
    real :: x
    x = a
    do while (x <= -pi)
      x = x + 2.0*pi
    end do
    do while (x > pi)
      x = x - 2.0*pi
    end do
    wrap_angle = x
  end function wrap_angle

  real function plaquette_avg_local(theta, L, Ntloc)
    implicit none
    integer, intent(in) :: L, Ntloc
    real, intent(in) :: theta(0:3,1:L,1:L,1:L,0:Ntloc+1)

    integer :: x,y,z,t, mu, nu
    integer :: xmu, ymu, zmu, tmu
    integer :: xnu, ynu, znu, tnu
    real :: thp
    real :: sumP
    integer :: countP

    sumP = 0.0
    countP = 0

    do t = 1, Ntloc
      do z = 1, L
        do y = 1, L
          do x = 1, L
            do mu = 0, 3
              do nu = mu+1, 3
                call shift_site(L, Ntloc, x,y,z,t, mu, +1, xmu,ymu,zmu,tmu)
                call shift_site(L, Ntloc, x,y,z,t, nu, +1, xnu,ynu,znu,tnu)

                thp = theta(mu,x,y,z,t) + theta(nu, xmu,ymu,zmu,tmu) - theta(mu, xnu,ynu,znu,tnu) - theta(nu,x,y,z,t)
                sumP = sumP + cos(thp)
                countP = countP + 1
              end do
            end do
          end do
        end do
      end do
    end do

    plaquette_avg_local = sumP / real(countP)
  end function plaquette_avg_local

end program u1_lattice_gauge
