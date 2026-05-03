// torus_rigid_body.sce
// Full Scilab script: inertia + rigid body dynamics for a solid torus

// ---------- PARAMETERS ----------
R = 2;    // major radius
r = 0.5;  // minor radius

// ---------- INTEGRAND ----------
function v = f(xyz, numfun)
    x = xyz(1);
    y = xyz(2);
    z = xyz(3);

    rho = 1;

    if ( (sqrt(x^2 + y^2) - R)^2 + z^2 <= r^2 ) then
        inside = 1;
    else
        inside = 0;
    end

    v = zeros(numfun,1);

    // mass + first moments
    v(1) = rho * inside;
    v(2) = x * rho * inside;
    v(3) = y * rho * inside;
    v(4) = z * rho * inside;

    // inertia components
    v(5) = (y^2 + z^2) * rho * inside;
    v(6) = (x^2 + z^2) * rho * inside;
    v(7) = (x^2 + y^2) * rho * inside;
    v(8) = -x*y * rho * inside;
    v(9) = -x*z * rho * inside;
    v(10)= -y*z * rho * inside;
endfunction

// ---------- INTEGRATION ----------
xmin = -(R + r);
xmax =  (R + r);
ymin = -(R + r);
ymax =  (R + r);
zmin = -r;
zmax =  r;

[result, err] = int3d(xmin,xmax, ymin,ymax, zmin,zmax, f, 10, [0,200000,1.d-5,1.d-6]);

// ---------- EXTRACT ----------
M  = result(1);

xc = result(2)/M;
yc = result(3)/M;
zc = result(4)/M;

I_origin = [ result(5)  result(8)  result(9)
             result(8)  result(6)  result(10)
             result(9)  result(10) result(7) ];

// shift to COM
A = [ yc^2 + zc^2,   -xc*yc,        -xc*zc
     -xc*yc,         xc^2 + zc^2,   -yc*zc
     -xc*zc,        -yc*zc,         xc^2 + yc^2 ];

I_com = I_origin - M * A;

disp("Mass:");
disp(M);

disp("Centre of mass:");
disp([xc yc zc]);

disp("Inertia tensor about COM:");
disp(I_com);

// ---------- PRINCIPAL AXES ----------
[V, D] = spec(I_com);
Ivals = diag(D);

I1 = Ivals(1);
I2 = Ivals(2);
I3 = Ivals(3);

disp("Principal moments:");
disp(Ivals);

// ---------- EULER DYNAMICS ----------
function dwdt = euler(t, w)
    w1 = w(1);
    w2 = w(2);
    w3 = w(3);

    dwdt = zeros(3,1);

    dwdt(1) = ((I2 - I3)/I1) * w2 * w3;
    dwdt(2) = ((I3 - I1)/I2) * w3 * w1;
    dwdt(3) = ((I1 - I2)/I3) * w1 * w2;
endfunction

// simulate
t = 0:0.01:10;
w0 = [1; 0.2; 2];

w = ode(w0, 0, t, euler);

// ---------- PLOT ----------
clf();
plot(t, w(1,:), 'r');
plot(t, w(2,:), 'g');
plot(t, w(3,:), 'b');
legend("w1","w2","w3");
xtitle("Angular velocity components vs time");
