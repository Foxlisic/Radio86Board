
        org     $F800

        ld      hl, $c001
        ld      (hl), $20   ; DISPLAY OFF

        jp      $
        ;; ---------

        ld      hl, $E6A0
        ld      de, 80*30   ; 2400
L1:     ld      (hl), '%'
        inc     hl
        dec     de
        ld      a, d
        or      e
        jp      nz, L1
        jp      $
