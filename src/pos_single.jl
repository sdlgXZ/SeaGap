#using Dates
#using Statistics
#using LinearAlgebra

export pos_single
function pos_single(lat,XDUCER_DEPTH=3.0,NPB=100::Int64; fn1="tr-ant.inp"::String,fn2="pxp-ini.xyh"::String,fn3="ss_prof.zv"::String,fn4="obsdata.inp"::String,eps=1.e-4,ITMAX=50::Int64, delta_pos = 1.e-4,fno0="log.txt"::String,fno1="solve.out"::String,fno2="position.out"::String,fno3="residual.out"::String,fno4="bspline.out"::String)
  println(stderr," === GNSS-A positioning: pos_single  ===")
  # --- Input check
  if XDUCER_DEPTH < 0
    error(" pos_single: XDUCER_DEPTH must be positive")
  end
  if NPB < 1
    error(" pos_single: NPB must be more than 1")
  end
  # --- Start log
  time1 = now()
  place = pwd()
  open(fno0,"w") do out0 
  println(out0,time1)
  println(out0,"pos_single.jl at $place")
  # --- Set parameters
  println(stderr," --- Set parameters")
  NC = 18
  dx = delta_pos; dy = delta_pos; dz = delta_pos
  println(out0,"Convergence_eps: $eps")
  println(out0,"Number_of_B-spline_knots: $NPB")
  println(out0,"Default_latitude: $lat")
  println(out0,"Maximum_iterations: $ITMAX")
  println(out0,"Delat_position: $delta_pos")
  println(out0,"XDUCER_DEPTH: $XDUCER_DEPTH")
  # --- Read data
  println(stderr," --- Read files")
  e = read_ant(fn1)
  numk, px, py, pz = read_pxppos(fn2)
  z, v, nz_st, numz = read_prof(fn3,XDUCER_DEPTH)
  num, nk, tp, t1, x1, y1, z1, h1, p1, r1, t2, x2, y2, z2, h2, p2, r2, nf = read_obsdata(fn4)
  NP0 = numk * 3
  # --- Fixed earth radius
  Rg, Rl = localradius(lat)

# --- Formatting --- #
  println(stderr," --- Initial formatting")
  # --- Calculate TR position
  println(stderr," --- Calculate TR positions")
  xd1 = zeros(num); xd2 = zeros(num)
  yd1 = zeros(num); yd2 = zeros(num)
  zd1 = zeros(num); zd2 = zeros(num)
  for i in 1:num
    xd1[i], yd1[i], zd1[i] = anttena2tr(x1[i],y1[i],z1[i],h1[i],p1[i],r1[i],e)
    xd2[i], yd2[i], zd2[i] = anttena2tr(x2[i],y2[i],z2[i],h2[i],p2[i],r2[i],e)
  end
  # --- Set mean xducer_height & TT corection
  println(stderr," --- TT corection")
  println(out0,"Travel-time correction: $NC")
  xducer_height = ( mean(zd1) + mean(zd2) ) / 2.0
  println(stderr,"     xducer_height:",xducer_height)
  Tv0 = zeros(numk); Vd = zeros(numk); Vr = zeros(numk); cc = zeros(numk,NC)
  for k in 1:numk
    Tv0[k], Vd[k], Vr[k], cc[k,1:NC], rms = ttcorrection(px[k],py[k],pz[k],xducer_height,z,v,nz_st,numz,XDUCER_DEPTH,lat)
    println(stderr,"     RMS for PxP-$k: ",rms)
    println(out0,"     RMS for PxP-$k: ",rms)
  end
  # --- Set B-spline function
  println(stderr," --- NTD basis")
  smin, smax, ds, tb = mktbasis(NPB,t1,t2,num)
  NPBV, id = retrieveb(NPB,tb,ds,t1,t2,num) 
  # --- Initialize
  NP = NP0 + NPBV
  d = zeros(num); H = zeros(num,NP); a0 = zeros(NP); a = zeros(NP)
  dc = zeros(num); dr = zeros(num); delta = 1.e6; rms = 1.e6
  sigma2 = 0.0; Hinv = zeros(num,NP)

# --- Main Anlysis --- #
  println(stderr," === Inversion")
  println(out0,"Start iteration")
  it = 1
  while delta > eps
    if it > ITMAX
      break
    end
    println(stderr," --- Iteration: $it")
    # --- Set H-matrix
    for n in 1:num
      k = nk[n]  # PXP number
      kx = (k - 1) * 3 + 1
      ky = (k - 1) * 3 + 2
      kz = (k - 1) * 3 + 3
      # --- Calculate TT
      tc1, to1, vert1 = xyz2tt_rapid(px[k]+a0[kx],py[k]+a0[ky],pz[k]+a0[kz],xd1[n],yd1[n],zd1[n],Rg,Tv0[k],Vd[k],Vr[k],xducer_height,cc[k,1:NC])
      tc2, to2, vert2 = xyz2tt_rapid(px[k]+a0[kx],py[k]+a0[ky],pz[k]+a0[kz],xd2[n],yd2[n],zd2[n],Rg,Tv0[k],Vd[k],Vr[k],xducer_height,cc[k,1:NC])
      vert = (vert1 + vert2) / 2.0
      tc = tc1 + tc2
      d[n] = (tp[n] - tc) * vert
      # --- Differential
      tcx1, to1, vert1 = xyz2tt_rapid(px[k]+a0[kx]+dx,py[k]+a0[ky],pz[k]+a0[kz],xd1[n],yd1[n],zd1[n],Rg,Tv0[k],Vd[k],Vr[k],xducer_height,cc[k,1:NC])
      tcx2, to2, vert2 = xyz2tt_rapid(px[k]+a0[kx]+dx,py[k]+a0[ky],pz[k]+a0[kz],xd2[n],yd2[n],zd2[n],Rg,Tv0[k],Vd[k],Vr[k],xducer_height,cc[k,1:NC])
      tcx = tcx1 + tcx2
      tcy1, to1, vert1 = xyz2tt_rapid(px[k]+a0[kx],py[k]+a0[ky]+dy,pz[k]+a0[kz],xd1[n],yd1[n],zd1[n],Rg,Tv0[k],Vd[k],Vr[k],xducer_height,cc[k,1:NC])
      tcy2, to2, vert2 = xyz2tt_rapid(px[k]+a0[kx],py[k]+a0[ky]+dy,pz[k]+a0[kz],xd2[n],yd2[n],zd2[n],Rg,Tv0[k],Vd[k],Vr[k],xducer_height,cc[k,1:NC])
      tcy = tcy1 + tcy2
      tcz1, to1, vert1 = xyz2tt_rapid(px[k]+a0[kx],py[k]+a0[ky],pz[k]+a0[kz]+dz,xd1[n],yd1[n],zd1[n],Rg,Tv0[k],Vd[k],Vr[k],xducer_height,cc[k,1:NC])
      tcz2, to2, vert2 = xyz2tt_rapid(px[k]+a0[kx],py[k]+a0[ky],pz[k]+a0[kz]+dz,xd2[n],yd2[n],zd2[n],Rg,Tv0[k],Vd[k],Vr[k],xducer_height,cc[k,1:NC])
      tcz = tcz1 + tcz2
      # --- Fill matrix
      H[n,kx] = (tcx-tc)/dx*vert; H[n,ky]=(tcy-tc)/dy*vert; H[n,kz]=(tcz-tc)/dz*vert
      if it == 1
        for m in 1:NPB
          if id[m] >= 1
            b0 = zeros(NPB)
            b0[m] = 1.0
            H[n,NP0+id[m]] = tbspline3((t1[n]+t2[n])/2.0,ds,tb,b0,NPB)
          end
        end
      end
    end
    Hinv = inv(transpose(H)*H)
    a = Hinv*transpose(H)*d
    dc = H*a
    dr = d - dc
    rms = std(dr)
    sa = num * rms^2
    sigma2 = sa / (num-NP)
    delta = std(a[1:NP0])
    a0[1:NP0] += a[1:NP0]
    a0[NP0+1:NP] = a[NP0+1:NP]
    println(stderr," Temporal position: $delta, $rms")
    println(out0,"     Iteration: $it $delta $rms")
    for k in 1:numk
      kx = (k - 1) * 3 + 1
      ky = (k - 1) * 3 + 2
      kz = (k - 1) * 3 + 3
      println(stderr,"    $(a0[kx]) $(a0[ky]) $(a0[kz])")
      println(out0,"    $(a0[kx]) $(a0[ky]) $(a0[kz])")
    end
    it += 1
  end
  println(stderr," End of loop ",it-1)
  println(stderr," --- Final position: $(a0[1:3]), $delta, $rms")
  println(out0,"End of iteration")
  cv = sqrt.(sigma2*abs.(diag(Hinv))) # Error
  a = transpose(a0[1:NP0])
  # --- Fill NTD basis
  b = zeros(NPB)
  for m in 1:NPB
    if id[m] >= 1
      b[m] = a0[NP0+id[m]]
    else
      b[m] = 0.0
    end
  end
  td = zeros(num)
  for n in 1:num
    td[n] = tbspline3((t1[n]+t2[n])/2.0,ds,tb,b,NPB)
  end

# --- Output --- #
  open(fno1,"w") do out
    Base.print_array(out,hcat(a0,cv))
  end
  open(fno2,"w") do out
    for k in 1:numk
      kx = (k - 1) * 3 + 1
      ky = (k - 1) * 3 + 2
      kz = (k - 1) * 3 + 3
      posx = px[k] + a[kx]
      posy = py[k] + a[ky]
      posz = pz[k] + a[kz]
      println(out,"$posx $posy $posz $(cv[kx]) $(cv[ky]) $(cv[kz])")
    end
  end
  open(fno3,"w") do out
    Base.print_array(out,hcat((t1+t2)/2.0,nk,d,dc,dr))
  end
  open(fno4,"w") do out
    Base.print_array(out,hcat(collect(1:NPB),id,tb,b))
  end

# --- Close process --- #
  time2 = now()
  println(stderr," Start time:",time1)
  println(stderr," Finish time:",time2)
  println(out0,time2)
  end
end
