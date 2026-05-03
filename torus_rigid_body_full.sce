// torus_rigid_body_full.sce
// Full simulation: torus inertia + rigid body dynamics + quaternion animation

// ---------- PARAMETERS ----------
R = 2;
r = 0.5;

// ---------- INTEGRAND ----------
function v = f(xyz, numfun)
    x = xyz(1); y = xyz(2); z = xyz(3);
    rho = 1;

    if ( (sqrt(x^2 + y^2) - R)^2 + z^2 <= r^2 ) then
        inside = 1;
    else
        inside = 0;
    end

    v = zeros(numfun,1);

    v(1) = rho * inside;
    v(2) = x * rho * inside;
    v(3) = y * rho * inside;
    v(4) = z * rho * inside;

    v(5) = (y^2 + z^2) * rho * inside;
    v(6) = (x^2 + z^2) * rho * inside;
    v(7) = (x^2 + y^2) * rho * inside;
    v(8) = -x*y * rho * inside;
    v(9) = -x*z * rho * inside;
    v(10)= -y*z * rho * inside;
endfunction

// ---------- INTEGRATION ----------
xmin = -(R + r); xmax = (R + r);
ymin = -(R + r); ymax = (R + r);
zmin = -r; zmax = r;

[result, err] = int3d(xmin,xmax, ymin,ymax, zmin,zmax, f, 10, [0,200000,1.d-5,1.d-6]);

M  = result(1);
xc = result(2)/M; yc = result(3)/M; zc = result(4)/M;

I_origin = [ result(5)  result(8)  result(9)
             result(8)  result(6)  result(10)
             result(9)  result(10) result(7) ];

A = [ yc^2 + zc^2,   -xc*yc,        -xc*zc
     -xc*yc,         xc^2 + zc^2,   -yc*zc
     -xc*zc,        -yc*zc,         xc^2 + yc^2 ];

I_com = I_origin - M * A;

// principal moments
[V, D] = spec(I_com);
Ivals = diag(D);

I1 = Ivals(1); I2 = Ivals(2); I3 = Ivals(3);

// ---------- EULER DYNAMICS ----------
function dwdt = euler(t, w)
    w1 = w(1); w2 = w(2); w3 = w(3);
    dwdt = zeros(3,1);

    dwdt(1) = ((I2 - I3)/I1) * w2 * w3;
    dwdt(2) = ((I3 - I1)/I2) * w3 * w1;
    dwdt(3) = ((I1 - I2)/I3) * w1 * w2;
endfunction

t = 0:0.02:10;
w0 = [1; 0.3; 2];
w = ode(w0, 0, t, euler);

// ---------- QUATERNIONS ----------
function q = quat_mult(q1, q2)
    w1=q1(1); x1=q1(2); y1=q1(3); z1=q1(4);
    w2=q2(1); x2=q2(2); y2=q2(3); z2=q2(4);

    q = [ w1*w2 - x1*x2 - y1*y2 - z1*z2;
          w1*x2 + x1*w2 + y1*z2 - z1*y2;
          w1*y2 - x1*z2 + y1*w2 + z1*x2;
          w1*z2 + x1*y2 - y1*x2 + z1*w2 ];
endfunction

function R = quat_to_rot(q)
    w=q(1); x=q(2); y=q(3); z=q(4);

    R = [1-2*(y^2+z^2), 2*(x*y - z*w), 2*(x*z + y*w);
         2*(x*y + z*w), 1-2*(x^2+z^2), 2*(y*z - x*w);
         2*(x*z - y*w), 2*(y*z + x*w), 1-2*(x^2+y^2)];
endfunction

function dqdt = quat_ode(ti, q)
    idx = max(1, min(size(w,2), int(ti/0.02)+1));
    wx = w(1,idx); wy = w(2,idx); wz = w(3,idx);
    omega = [0; wx; wy; wz];
    dqdt = 0.5 * quat_mult(q, omega);
endfunction

q0 = [1;0;0;0];
q = ode(q0, 0, t, quat_ode);

// ---------- TORUS MESH ----------
function [X,Y,Z] = torus_mesh(R, r, nu, nv)
    u = linspace(0, 2*%pi, nu);
    v = linspace(0, 2*%pi, nv);

    X = zeros(nu,nv);
    Y = zeros(nu,nv);
    Z = zeros(nu,nv);

    for i=1:nu
        for j=1:nv
            X(i,j) = (R + r*cos(v(j))) * cos(u(i));
            Y(i,j) = (R + r*cos(v(j))) * sin(u(i));
            Z(i,j) = r * sin(v(j));
        end
    end
endfunction

[X0,Y0,Z0] = torus_mesh(R, r, 40, 20);

// ---------- ANIMATION ----------
clf();
for k = 1:5:length(t)
    qk = q(:,k);
    qk = qk / norm(qk);
    Rmat = quat_to_rot(qk);

    X = zeros(X0);
    Y = zeros(Y0);
    Z = zeros(Z0);

    for i=1:size(X0,1)
        for j=1:size(X0,2)
            p = [X0(i,j); Y0(i,j); Z0(i,j)];
            p2 = Rmat * p;

            X(i,j) = p2(1);
            Y(i,j) = p2(2);
            Z(i,j) = p2(3);
        end
    end

    clf();
    surf(X,Y,Z);
    axis equal;
    xtitle("Spinning torus (rigid body)");

    sleep(20);
end
